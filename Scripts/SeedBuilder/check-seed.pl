#!/usr/bin/env perl
use strict;
use warnings;
use v5.36;
use JSON::XS qw(decode_json);

my $path = $ARGV[0] // "Chess Openings/Resources/openings.json";
open my $fh, "<", $path or die "open $path: $!";
local $/;
my $data = decode_json(scalar <$fh>);

my $errors = 0;
sub fail { $errors++; warn "FAIL: $_[0]\n"; }

# Read the catalogue so per-opening line-count expectations come from
# the same source the builder used. Each catalogue entry produces
# (lineCount × 2) lines (masters + online); we tolerate a margin
# because the open source occasionally returns fewer candidates.
my $cat_path = "Scripts/SeedBuilder/seed-catalogue.json";
open my $cfh, "<", $cat_path or die "open $cat_path: $!";
local $/;
my $cat = decode_json(scalar <$cfh>);
my $expected_openings = scalar @{$cat->{openings}};
my %expected_lineCount = map { $_->{name} => $_->{lineCount} } @{$cat->{openings}};

fail("expected $expected_openings openings, got " . scalar @{$data->{openings}})
    if scalar @{$data->{openings}} != $expected_openings;

for my $o (@{$data->{openings}}) {
    fail("opening missing name") unless defined $o->{name};
    fail("$o->{name}: missing eco") unless defined $o->{eco};
    fail("$o->{name}: side must be white/black") unless $o->{side} =~ /^(white|black)$/;

    my $target = $expected_lineCount{$o->{name}};
    if (defined $target) {
        my $lo = $target * 2 - 2;       # tolerate -2 lines (open source thin)
        my $hi = $target * 2;
        my $got = scalar @{$o->{lines}};
        fail("$o->{name}: expected $lo-$hi lines (target lineCount=$target), got $got")
            if $got < $lo || $got > $hi;
    } else {
        fail("$o->{name}: not in catalogue");
    }

    my %by_source;
    $by_source{$_->{source} // "missing"}++ for @{$o->{lines}};
    fail("$o->{name}: expected >=1 masters line, got " . ($by_source{masters} // 0)) if ($by_source{masters} // 0) < 1;
    fail("$o->{name}: expected >=1 open line, got " . ($by_source{open} // 0)) if ($by_source{open} // 0) < 1;

    for my $l (@{$o->{lines}}) {
        fail("$o->{name}/$l->{name}: missing source") unless defined $l->{source};
        fail("$o->{name}/$l->{name}: invalid source '$l->{source}'") unless $l->{source} =~ /^(masters|open)$/;
        fail("$o->{name}: empty plies") unless @{$l->{plies}};
        fail("$o->{name}/$l->{name}: >20 plies (" . scalar @{$l->{plies}} . ")") if @{$l->{plies}} > 20;
        for my $p (@{$l->{plies}}) {
            fail("$o->{name}/$l->{name}: ply missing san") unless defined $p->{san};
            fail("$o->{name}/$l->{name}: ply missing uci") unless defined $p->{uci} && length $p->{uci};
        }
    }
}

if ($errors) {
    die "$errors error(s)\n";
} else {
    print "ok: $expected_openings openings validated\n";
}
