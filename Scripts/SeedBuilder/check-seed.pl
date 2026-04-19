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

fail("expected 16 openings, got " . scalar @{$data->{openings}}) if scalar @{$data->{openings}} != 16;

for my $o (@{$data->{openings}}) {
    fail("opening missing name") unless defined $o->{name};
    fail("$o->{name}: missing eco") unless defined $o->{eco};
    fail("$o->{name}: side must be white/black") unless $o->{side} =~ /^(white|black)$/;
    fail("$o->{name}: expected 8-10 lines, got " . scalar @{$o->{lines}}) if @{$o->{lines}} < 8 || @{$o->{lines}} > 10;

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
    print "ok: 16 openings validated\n";
}
