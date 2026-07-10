package Koha::Plugin::SeedCataloguing;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use JSON;
use MARC::Record;
use MARC::Field;
use C4::Context;
use C4::Matcher;
use C4::ImportBatch qw(
    AddImportBatch GetImportBatch AddBiblioToBatch BatchFindDuplicates
);
use Koha::Token;

# Code of the Record Matching Rule used to detect already-catalogued taxa
# (matches on 110$0, the CoL taxon URI — see memory_lecat/koha-opensearch-gotchas.md).
use constant SEED_MATCHER_CODE => 'SEEDCOL';

use Koha::Plugin::SeedCataloguing::Source::CoL;
use Koha::Plugin::SeedCataloguing::MARCBuilder;

our $VERSION = '0.1';
our $metadata = {
    name            => 'Seed Cataloguing Tool',
    author          => 'Sebastiano Midolo / EBo',
    description     => 'Fetch species data from Catalogue of Life and create seed-library MARC records',
    date_authored   => '2026-07-06',
    date_updated    => '2026-07-06',
    minimum_version => '25.11',
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ($class, $args) = @_;
    $args->{metadata} = $metadata;
    return $class->SUPER::new($args);
}

# ---------------------------------------------------------------
# MAIN TOOL ENTRY POINT
# ---------------------------------------------------------------
sub tool {
    my ($self, $args) = @_;
    my $cgi = $self->{cgi};

    my $search_name = $cgi->param('search_name') // '';
    my $taxon_id    = $cgi->param('taxon_id')    // '';
    my $confirm     = $cgi->param('confirm')     // '';
    my $source      = $cgi->param('source')      // 'catl';

    # Step 1: no input → search form
    unless ($search_name || $taxon_id) {
        return $self->output_html($self->_search_form_template());
    }

    # Step 2: have search name but no taxon selected → results list
    if ($search_name && !$taxon_id) {
        my $data = $self->_do_search($source, $search_name);
        return $self->output_html(
            ref $data eq 'HASH' && $data->{error}
                ? $self->_error_template($data->{error})
                : $self->_results_template($data->{results}, $search_name, $source,
                                           $data->{url}, $data->{raw})
        );
    }

    # Step 3: taxon selected but not confirmed → MARC preview
    if ($taxon_id && !$confirm) {
        my $species = $self->_do_fetch($source, $taxon_id);
        return $self->output_html($self->_error_template($species->{error}))
            if ref $species eq 'HASH' && $species->{error};
        my $record = Koha::Plugin::SeedCataloguing::MARCBuilder->build($species);
        return $self->output_html(
            $self->_preview_template($species, $record, $taxon_id, $source));
    }

    # Step 4: confirmed → create record
    if ($taxon_id && $confirm) {
        die "CSRF check failed"
            unless Koha::Token->new->check_csrf({
                session_id => scalar $cgi->cookie('CGISESSID'),
                token      => scalar $cgi->param('csrf_token'),
            });

        my $species = $self->_do_fetch($source, $taxon_id);
        return $self->output_html($self->_error_template($species->{error}))
            if ref $species eq 'HASH' && $species->{error};

        my $record = Koha::Plugin::SeedCataloguing::MARCBuilder->build($species);

        my $batch_id = eval { $self->_stage_record($record) };
        if ($@ || !$batch_id) {
            my $err = $@ || 'unknown error';
            return $self->output_html(
                $self->_error_template("Staging failed — record not added: $err"));
        }

        print $cgi->redirect(
            "/cgi-bin/koha/tools/manage-marc-import.pl?import_batch_id=$batch_id");
        return;
    }
}

# ---------------------------------------------------------------
# STAGE the built record into the plugin's persistent import batch
# (one shared batch across confirms; a human reviews/commits it later
# via Tools > Manage staged MARC records). Never calls AddBiblio directly
# — this is how we avoid creating duplicate taxa in the catalog.
# ---------------------------------------------------------------
sub _stage_record {
    my ($self, $record) = @_;

    my $matcher_id = C4::Matcher::GetMatcherId(SEED_MATCHER_CODE)
        or die 'Record Matching Rule "' . SEED_MATCHER_CODE . '" not found — run the setup step first';

    my $batch_id = $self->retrieve_data('import_batch_id');
    my $batch    = $batch_id ? GetImportBatch($batch_id) : undef;

    unless ($batch) {
        $batch_id = AddImportBatch({
            record_type    => 'biblio',
            batch_type     => 'batch',
            import_status  => 'staged',
            overlay_action => 'ignore',       # a match exists → don't touch it, let the librarian decide
            nomatch_action => 'create_new',   # no match → genuinely new taxon, fine to add
            item_action    => 'ignore',       # no items at this stage
            matcher_id     => $matcher_id,
            file_name      => 'Seed Cataloguing Tool',
            comments       => 'Staged by the Seed Cataloguing Tool plugin',
        });
        $self->store_data({ import_batch_id => $batch_id });
    }

    my $dbh = C4::Context->dbh;
    my ($max_seq) = $dbh->selectrow_array(
        'SELECT MAX(record_sequence) FROM import_records WHERE import_batch_id = ?',
        undef, $batch_id);
    my $seq = ($max_seq // 0) + 1;

    AddBiblioToBatch($batch_id, $seq, $record, 'UTF-8', 1);

    my $matcher = C4::Matcher->fetch($matcher_id);
    BatchFindDuplicates($batch_id, $matcher, 10);

    return $batch_id;
}

# ---------------------------------------------------------------
# SOURCE DISPATCH
# ---------------------------------------------------------------
sub _do_search {
    my ($self, $source, $name) = @_;
    if ($source eq 'catl') {
        return Koha::Plugin::SeedCataloguing::Source::CoL->search($name);
    }
    return { error => "Unknown source: $source" };
}

sub _do_fetch {
    my ($self, $source, $id) = @_;
    if ($source eq 'catl') {
        my $sp = Koha::Plugin::SeedCataloguing::Source::CoL->fetch($id);
        return $sp // { error => "Taxon '$id' not found in Catalogue of Life" };
    }
    return { error => "Unknown source: $source" };
}

# ---------------------------------------------------------------
# MARC PREVIEW HELPER: fields → HTML rows
# ---------------------------------------------------------------
sub _record_to_html {
    my ($self, $record) = @_;
    my $html = '';
    for my $field ($record->fields()) {
        if ($field->is_control_field()) {
            my $tag  = $self->_esc($field->tag());
            my $data = $self->_esc($field->data());
            $html .= "<tr><td><b>$tag</b></td><td></td><td>$data</td></tr>\n";
        } else {
            my $tag  = $self->_esc($field->tag());
            my $ind  = $self->_esc($field->indicator(1)) . $self->_esc($field->indicator(2));
            my $subs = join(' ', map { '<b>$' . $_->[0] . '</b> ' . $self->_esc($_->[1]) }
                            $field->subfields());
            $html .= "<tr><td><b>$tag</b></td><td>$ind</td><td>$subs</td></tr>\n";
        }
    }
    return $html;
}

sub _esc {
    my ($self, $s) = @_;
    $s //= '';
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    return $s;
}

# ---------------------------------------------------------------
# TEMPLATES
# ---------------------------------------------------------------
sub _search_form_template {
    my ($self) = @_;
    my $csrf_token = Koha::Token->new->generate_csrf(
        { session_id => scalar $self->{cgi}->cookie('CGISESSID') });
    return <<"HTML";
<!DOCTYPE html>
<html>
<head>
  <title>Seed Cataloguing Tool</title>
  <style>
    body { font-family: sans-serif; margin: 2em; }
    label { display: block; margin: 1em 0 0.3em; }
    input[type=text] { width: 40em; padding: 0.3em; }
    input[type=submit] { margin-top: 1em; padding: 0.4em 1.2em; }
    .note { color: #666; font-size: 0.9em; margin-top: 0.5em; }
  </style>
</head>
<body>
<h1>Seed Cataloguing Tool</h1>
<p>Search Catalogue of Life for a plant species and generate a seed-library MARC record.</p>
<form method="post">
  <input type="hidden" name="csrf_token" value="$csrf_token"/>
  <input type="hidden" name="class"  value="Koha::Plugin::SeedCataloguing"/>
  <input type="hidden" name="method" value="tool"/>
  <input type="hidden" name="source" value="catl"/>
  <label for="search_name">Scientific name (or partial name):</label>
  <input type="text" id="search_name" name="search_name"
         placeholder="e.g. Sanguinaria canadensis"/>
  <p class="note">Source: <a href="https://www.catalogueoflife.org/" target="_blank">Catalogue of Life</a> (catl)</p>
  <input type="submit" value="Search"/>
</form>
</body>
</html>
HTML
}

sub _results_template {
    my ($self, $results, $search_name, $source, $query_url, $raw) = @_;
    my $csrf_token = Koha::Token->new->generate_csrf(
        { session_id => scalar $self->{cgi}->cookie('CGISESSID') });
    my $name_esc = $self->_esc($search_name);
    my $src_esc  = $self->_esc($source);
    my $url_esc  = $self->_esc($query_url // '');
    my $raw_json = $raw ? JSON->new->pretty->canonical->encode($raw) : '';
    $raw_json    =~ s/&/&amp;/g;
    $raw_json    =~ s/</&lt;/g;
    $raw_json    =~ s/>/&gt;/g;

    unless (@$results) {
        return <<"HTML";
<!DOCTYPE html><html><body>
<h2>No results for &ldquo;$name_esc&rdquo;</h2>
<p>Try a different spelling or a partial name (e.g. just the genus).</p>
<p>Query URL: <a href="$url_esc" target="_blank">$url_esc</a></p>
<a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ASeedCataloguing&amp;method=tool">Search again</a>
</body></html>
HTML
    }

    my $rows = '';
    for my $r (@$results) {
        my $id     = $self->_esc($r->{id});
        my $label  = $self->_esc($r->{label});
        my $rank   = $self->_esc($r->{rank}   // '');
        my $status = $self->_esc($r->{status} // '');
        $rows .= <<"ROW";
<tr>
  <td><input type="radio" name="taxon_id" value="$id" required/></td>
  <td><i><a href="https://www.catalogueoflife.org/data/taxon/$id" target="_blank">$label</a></i></td>
  <td>$rank</td>
  <td>$status</td>
</tr>
ROW
    }

    return <<"HTML";
<!DOCTYPE html>
<html>
<head>
  <title>Search results — Seed Cataloguing</title>
  <style>
    body { font-family: sans-serif; margin: 2em; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #ccc; padding: 0.4em 0.8em; text-align: left; }
    th { background: #eee; }
    input[type=submit] { margin-top: 1em; padding: 0.4em 1.2em; }
    .raw-section { margin-top: 2em; }
    .raw-section summary { cursor: pointer; color: #555; font-size: 0.9em; }
    .raw-section pre { background: #f5f5f5; border: 1px solid #ddd;
                       padding: 0.8em; overflow-x: auto; font-size: 0.8em;
                       max-height: 30em; overflow-y: auto; }
    .query-url { margin-top: 1.5em; font-size: 0.9em; color: #555; }
  </style>
</head>
<body>
<h1>Results for &ldquo;$name_esc&rdquo;</h1>
<form method="post">
  <input type="hidden" name="csrf_token" value="$csrf_token"/>
  <input type="hidden" name="class"  value="Koha::Plugin::SeedCataloguing"/>
  <input type="hidden" name="method" value="tool"/>
  <input type="hidden" name="source" value="$src_esc"/>
  <table>
    <thead><tr><th></th><th>Scientific name</th><th>Rank</th><th>Status</th></tr></thead>
    <tbody>$rows</tbody>
  </table>
  <input type="submit" value="Show MARC preview &rarr;"/>
  &nbsp;
  <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ASeedCataloguing&amp;method=tool">New search</a>
</form>

<p class="query-url">API query: <a href="$url_esc" target="_blank">$url_esc</a></p>

<details class="raw-section">
  <summary>Raw API response (JSON)</summary>
  <pre>$raw_json</pre>
</details>

</body>
</html>
HTML
}

sub _preview_template {
    my ($self, $species, $record, $taxon_id, $source) = @_;
    my $csrf_token = Koha::Token->new->generate_csrf(
        { session_id => scalar $self->{cgi}->cookie('CGISESSID') });
    my $name_esc   = $self->_esc($species->{scientific_name});
    my $id_esc     = $self->_esc($taxon_id);
    my $src_esc    = $self->_esc($source);
    my $marc_rows  = $self->_record_to_html($record);

    my $common_str = join(', ', map { $self->_esc($_) } @{ $species->{common_names} // [] });
    my $syn_str    = join('; ', map { $self->_esc($_) } @{ $species->{synonyms}     // [] });

    return <<"HTML";
<!DOCTYPE html>
<html>
<head>
  <title>MARC preview — $name_esc</title>
  <style>
    body { font-family: sans-serif; margin: 2em; }
    h2   { margin-top: 1.5em; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 1em; }
    th, td { border: 1px solid #ccc; padding: 0.3em 0.7em; vertical-align: top; }
    th { background: #eee; text-align: left; }
    td:first-child { white-space: nowrap; }
    .actions { margin-top: 1.5em; }
    .actions input[type=submit] { padding: 0.5em 1.5em; font-size: 1.05em; }
  </style>
</head>
<body>
<h1>MARC preview</h1>
<h2><i>$name_esc</i></h2>
<table>
  <tr><th>Common names</th><td>$common_str</td></tr>
  <tr><th>Synonyms</th><td>$syn_str</td></tr>
  <tr><th>Authority URI</th><td><a href="${\$self->_esc($species->{authority_uri})}" target="_blank">${\$self->_esc($species->{authority_uri})}</a></td></tr>
  <tr><th>Source</th><td>$src_esc</td></tr>
</table>

<h2>MARC fields</h2>
<table>
  <thead><tr><th>Tag</th><th>Ind</th><th>Content</th></tr></thead>
  <tbody>$marc_rows</tbody>
</table>

<div class="actions">
<form method="post">
  <input type="hidden" name="class"      value="Koha::Plugin::SeedCataloguing"/>
  <input type="hidden" name="method"     value="tool"/>
  <input type="hidden" name="source"     value="$src_esc"/>
  <input type="hidden" name="taxon_id"   value="$id_esc"/>
  <input type="hidden" name="confirm"    value="1"/>
  <input type="hidden" name="csrf_token" value="$csrf_token"/>
  <input type="submit" value="Insert MARC record"/>
  &nbsp;
  <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ASeedCataloguing&amp;method=tool">New search</a>
</form>
</div>
</body>
</html>
HTML
}

sub _error_template {
    my ($self, $msg) = @_;
    my $msg_esc = $self->_esc($msg);
    return <<"HTML";
<!DOCTYPE html><html><body>
<h2>Error</h2>
<p>$msg_esc</p>
<a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ASeedCataloguing&amp;method=tool">Try again</a>
</body></html>
HTML
}

# ---------------------------------------------------------------
# CONFIGURE (minimal — no API key needed for CoL)
# ---------------------------------------------------------------
sub configure {
    my ($self, $args) = @_;
    my $cgi = $self->{cgi};

    if ($cgi->param('save')) {
        die "CSRF check failed"
            unless Koha::Token->new->check_csrf({
                session_id => scalar $cgi->cookie('CGISESSID'),
                token      => scalar $cgi->param('csrf_token'),
            });
        $self->store_data({
            default_source => scalar $cgi->param('default_source') // 'catl',
        });
    }

    my $csrf_token    = Koha::Token->new->generate_csrf(
        { session_id => scalar $cgi->cookie('CGISESSID') });
    my $default_src   = $self->retrieve_data('default_source') // 'catl';

    $self->output_html(<<"HTML");
<!DOCTYPE html>
<html>
<head><title>Configure Seed Cataloguing Tool</title></head>
<body>
<h1>Configure Seed Cataloguing Tool</h1>
<form method="post">
  <input type="hidden" name="csrf_token" value="$csrf_token"/>
  <input type="hidden" name="class"  value="Koha::Plugin::SeedCataloguing"/>
  <input type="hidden" name="method" value="configure"/>
  <input type="hidden" name="save"   value="1"/>
  <p>
    <label>Default source:
      <select name="default_source">
        <option value="catl"${\$default_src eq 'catl' ? ' selected' : ''}>Catalogue of Life (catl)</option>
      </select>
    </label>
  </p>
  <p><em>The Catalogue of Life API is open and requires no key.</em></p>
  <input type="submit" value="Save"/>
</form>
</body>
</html>
HTML
}

sub install   { return 1; }
sub upgrade   { return 1; }
sub uninstall { return 1; }

1;
