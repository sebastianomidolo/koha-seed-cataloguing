package Koha::Plugin::SeedCataloguing::Source::CoL;

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use URI::Escape qw(uri_escape);

# Catalogue of Life / ChecklistBank driver.
# Returns a source-agnostic normalised hash suitable for MARCBuilder::build().
#
# CoL dataset in ChecklistBank: 3LR (latest release)
# Base URL: https://api.checklistbank.org/dataset/3LR

my $BASE   = 'https://api.checklistbank.org/dataset/3LXR';
my $COL_UI = 'https://www.catalogueoflife.org/data/taxon';

# search($name) → arrayref of { id, label, rank, status }
# Used to populate the results list in the plugin UI.
# search($name) → { results => [...], url => $str, raw => $hashref }
sub search {
    my ($class, $name) = @_;

    my $q    = uri_escape($name);
    my $url_exact    = "$BASE/nameusage/search?q=$q&limit=15&type=EXACT";
    my $url_fallback = "$BASE/nameusage/search?q=$q&limit=15";

    my ($json, $url_used);
    $json = _api_get($url_exact);
    if ($json && $json->{result} && @{ $json->{result} }) {
        $url_used = $url_exact;
    } else {
        $json     = _api_get($url_fallback);
        $url_used = $url_fallback;
    }

    my @results;
    if ($json && $json->{result}) {
        for my $r (@{ $json->{result} }) {
            my $usage = $r->{usage} // $r;
            my $nm    = $usage->{name} // {};
            my $id    = $usage->{id}   // next;
            push @results, {
                id     => $id,
                label  => $nm->{scientificName} // $nm->{label} // $id,
                rank   => lc($nm->{rank} // ''),
                status => lc($usage->{status} // ''),
            };
        }
    }

    return {
        results  => \@results,
        url      => $url_used,
        raw      => $json,
    };
}

# fetch($id) → normalised species hash, or undef on error.
sub fetch {
    my ($class, $id) = @_;

    my $taxon = _api_get("$BASE/taxon/$id")          or return undef;
    my $class_data = _api_get("$BASE/taxon/$id/classification") // [];
    my $info       = _api_get("$BASE/taxon/$id/info")           // {};
    my $synonyms   = _api_get("$BASE/taxon/$id/synonym")       // {};

    my $nm = $taxon->{name} // {};

    # Build classification list, kingdom → species (ascending order from API)
    my @classification;
    for my $level (reverse @{ _ensure_array($class_data) }) {
        # CoL sometimes returns `name` as a nested object (rank/scientificName/
        # uninomial), but for some infrafamilial ranks (e.g. tribes like
        # "Chelidonieae") it's just a bare string. Handle both.
        my $name_field = $level->{name};
        my $ln = (ref $name_field eq 'HASH') ? $name_field : undef;
        my $rank = lc(($ln ? $ln->{rank} : undef) // $level->{rank} // '');
        my $sci  = $ln
            ? ($ln->{scientificName} // $ln->{label} // '')
            : (defined $name_field ? "$name_field" : '');
        # For genus and above, strip authorship — use only the uninomial
        my $display = ($rank eq 'species') ? $sci
                    : (($ln && $ln->{uninomial}) // ($sci =~ /^(\S+)/)[0] // $sci);
        push @classification, { rank => $rank, name => $display }
            if $rank && $display;
    }

    # Add species itself at the end if not already there
    if ($nm->{rank} && lc($nm->{rank}) eq 'species') {
        my $epithet = $nm->{specificEpithet} // '';
        push @classification, { rank => 'species', name => $epithet }
            if $epithet && !grep { $_->{rank} eq 'species' } @classification;
    }

    # Common names from /info endpoint (prefer English).
    # 3LXR returns two formats: structured {"name":"bloodroot","language":"eng"}
    # and inline-suffix {"name":"Bloodroot (EN)"}. Handle both.
    my @common;
    my @vnames = @{ _ensure_array($info->{vernacularNames}) };
    my @en = map  { _strip_lang_suffix($_->{name}) }
             grep { _is_english($_) } @vnames;
    my @ot = map  { _strip_lang_suffix($_->{name}) }
             grep { !_is_english($_) } @vnames;
    @common = (@en, @ot);

    # Synonyms
    my @syn_names;
    my $syn_list = $synonyms->{result} // $synonyms;
    for my $s (@{ _ensure_array($syn_list) }) {
        my $sn = $s->{name} // $s;
        push @syn_names, $sn->{scientificName} if $sn->{scientificName};
    }

    # Distribution — CoL provides it as a structured field or free text
    my $distrib = '';
    if (ref $taxon->{distributions} eq 'ARRAY' && @{ $taxon->{distributions} }) {
        $distrib = join('; ', map { $_->{area}{name} // $_->{verbatimArea} // '' }
                        @{ $taxon->{distributions} });
    }

    return {
        scientific_name => $nm->{scientificName} // '',
        common_names    => \@common,
        authority_uri   => "$COL_UI/$id",
        external_uris   => [],          # CoL doesn't expose POWO links via API
        source_code     => 'catl',
        synonyms        => \@syn_names,
        published_in    => $nm->{publishedInYear}
                           ? "Published $nm->{publishedInYear}"
                           : '',
        distribution    => $distrib,
        classification  => \@classification,
        _raw_taxon      => $taxon,      # kept for debugging, not used by MARCBuilder
    };
}

# -------------------------------------------------------------------
sub _api_get {
    my ($url) = @_;
    my $ua = LWP::UserAgent->new(timeout => 20, agent => 'Koha-SeedCataloguing/0.1');
    $ua->default_header(Accept => 'application/json');
    my $resp = $ua->get($url);
    return undef unless $resp->is_success;
    my $data = eval { decode_json($resp->decoded_content) };
    return $@ ? undef : $data;
}

sub _is_english {
    my ($v) = @_;
    return 1 if ($v->{language} // '') =~ /^eng?$/i;   # structured field
    return 1 if ($v->{name}     // '') =~ /\(EN\)/i;   # inline suffix fallback
    return 0;
}

sub _strip_lang_suffix {
    my ($s) = @_;
    $s //= '';
    $s =~ s/\s*\([A-Z]{2}\)\s*$//;
    return $s;
}

sub _ensure_array {
    my ($v) = @_;
    return []   unless defined $v;
    return $v   if ref $v eq 'ARRAY';
    return [$v] if ref $v eq 'HASH';
    return [];
}

1;
