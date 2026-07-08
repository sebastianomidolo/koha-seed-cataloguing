package Koha::Plugin::SeedCataloguing::MARCBuilder;

use Modern::Perl;
use MARC::Record;
use MARC::Field;

# Build a complete MARC bibliographic record from a normalised species hash.
# The hash structure is source-agnostic — see Source/*.pm for how each
# driver populates it.

sub build {
    my ($class, $species) = @_;

    my $record = MARC::Record->new();
    $record->leader('00000nam a2200000 a 4500');

    my @fields;

    # --- Control fields ---
    # No 001/003: duplicate detection uses the 110$0 CoL taxon URI directly
    # (Record Matching Rule "SEEDCOL"), not a synthetic control number.
    push @fields, MARC::Field->new('008', _build_008());

    # --- Cataloguing source ---
    push @fields, MARC::Field->new('040', ' ', ' ',
        a => 'Koha-Seed',
        b => 'eng',
        c => 'Koha-Seed',
    );

    # --- 110: Species as corporate name (ind1=2: name in direct order) ---
    my @f110 = (a => $species->{scientific_name});
    if (my $common = $species->{common_names}[0]) {
        push @f110, b => $common;
    }
    push @f110, '0' => $species->{authority_uri}  if $species->{authority_uri};
    push @f110, '1' => $species->{external_uris}[0] if $species->{external_uris}[0];
    push @f110, '2' => $species->{source_code}    if $species->{source_code};
    push @fields, MARC::Field->new('110', '2', ' ', @f110);

    # --- 245: Title (collection event stub — to be completed at import time) ---
    push @fields, MARC::Field->new('245', '1', '0',
        a => 'Seed collection :',
        b => $species->{scientific_name},
    );

    # --- 251: Version tag ---
    push @fields, MARC::Field->new('251', ' ', ' ',
        a => '0.1',
        '2' => 'Koha_Seed',
    );

    # --- 500: Synonym note ---
    if ($species->{synonyms} && @{ $species->{synonyms} }) {
        my $syn_list = join('; ', @{ $species->{synonyms} });
        push @fields, MARC::Field->new('500', ' ', ' ',
            a => "Synonyms: $syn_list",
        );
    }

    # --- 510: Nomenclatural reference ---
    if ($species->{published_in}) {
        push @fields, MARC::Field->new('510', '4', ' ',
            a => $species->{published_in},
        );
    }

    # --- 522: Geographic distribution ---
    if ($species->{distribution}) {
        push @fields, MARC::Field->new('522', ' ', ' ',
            a => $species->{distribution},
        );
    }

    # --- 754: Taxonomic identification ---
    # $c/$a pairs in hierarchical order, then $d (common name), $0, $2
    if ($species->{classification} && @{ $species->{classification} }) {
        my @f754;
        for my $level (@{ $species->{classification} }) {
            push @f754, c => $level->{rank};
            push @f754, a => $level->{name};
        }
        for my $common (@{ $species->{common_names} // [] }) {
            push @f754, d => $common;
        }
        push @f754, '0' => $species->{authority_uri} if $species->{authority_uri};
        push @f754, '2' => $species->{source_code}   if $species->{source_code};
        push @fields, MARC::Field->new('754', ' ', ' ', @f754);
    }

    # --- 942: Koha item type ---
    push @fields, MARC::Field->new('942', ' ', ' ', c => 'SEED');

    $record->append_fields(@fields);
    return $record;
}

sub _build_008 {
    my @t   = localtime(time);
    my $yy  = sprintf('%02d', $t[5] % 100);
    my $mm  = sprintf('%02d', $t[4] + 1);
    my $dd  = sprintf('%02d', $t[3]);
    my $yr4 = sprintf('%04d', $t[5] + 1900);
    return "${yy}${mm}${dd}s${yr4}    xx            000 0 eng d";
}

1;
