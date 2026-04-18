#!/usr/bin/env perl
use strict;
use warnings;
use v5.36;
use HTTP::Tiny;
use JSON::XS qw(decode_json encode_json);
use File::Path qw(make_path);
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(sleep);

my $CATALOGUE = "Scripts/SeedBuilder/seed-catalogue.json";
my $ANNOTS    = "Scripts/SeedBuilder/annotations.json";
my $CACHE_DIR = "Scripts/SeedBuilder/.seed-cache";
my $LOG_PATH  = "Scripts/SeedBuilder/build-seed.log";
my $OUT_PATH  = "Chess Openings/Resources/openings.json";
my $MAX_PLIES = 20;
my $MIN_GAMES = 50;
my $API       = "https://explorer.lichess.ovh/masters";

make_path($CACHE_DIR);
make_path("Chess Openings/Resources");

open my $LOG, ">", $LOG_PATH or die "open log $LOG_PATH: $!";
my $old_fh = select($LOG); $| = 1; select($old_fh);

sub logmsg {
    my ($msg) = @_;
    my @t = localtime;
    my $ts = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
    my $line = "[$ts] $msg\n";
    print $LOG $line;
    print STDERR $line;
}

logmsg("build-seed.pl starting");

my $http = HTTP::Tiny->new(agent => "chess-openings-seed/1.0", timeout => 30);

my $AUTH_HEADER;
my $TOKEN_PATH = "lichess-api-key.txt";
if (-e $TOKEN_PATH) {
    open my $tfh, "<", $TOKEN_PATH or die "open $TOKEN_PATH: $!";
    my $tok = <$tfh>;
    close $tfh;
    chomp $tok if defined $tok;
    $tok =~ s/^\s+|\s+$//g if defined $tok;
    if (defined $tok && length $tok) {
        $AUTH_HEADER = "Bearer $tok";
        logmsg("using lichess api token from $TOKEN_PATH");
    }
}
logmsg("no lichess api token found — using anonymous requests") unless $AUTH_HEADER;

sub load_json {
    my ($p) = @_;
    open my $fh, "<", $p or die "open $p: $!";
    local $/;
    decode_json(scalar <$fh>);
}

my $cat    = load_json($CATALOGUE);
my $annots = load_json($ANNOTS)->{annotations};

my $req_count   = 0;
my $cache_hits  = 0;
my $cache_miss  = 0;

sub explorer {
    my (%q) = @_;
    $req_count++;
    my $key  = md5_hex(join("|", map { "$_=$q{$_}" } sort keys %q));
    my $file = "$CACHE_DIR/$key.json";
    my $play_preview = $q{play} // "";
    $play_preview = substr($play_preview, 0, 60) . "..." if length($play_preview) > 60;
    if (-e $file) {
        $cache_hits++;
        logmsg("  explorer #$req_count CACHE play=[$play_preview]");
        open my $fh, "<", $file; local $/; return decode_json(scalar <$fh>);
    }
    $cache_miss++;
    my $url = $API . "?" . join("&", map { "$_=$q{$_}" } sort keys %q);
    logmsg("  explorer #$req_count FETCH play=[$play_preview]");
    sleep(1);
    my %opts;
    $opts{headers} = { Authorization => $AUTH_HEADER } if $AUTH_HEADER;
    my $res = $http->get($url, \%opts);
    die "explorer $url: $res->{status} $res->{reason}" unless $res->{success};
    open my $fh, ">", $file; print $fh $res->{content}; close $fh;
    decode_json($res->{content});
}

sub walk_line {
    my ($opening_name, $history_uci, $depth) = @_;
    return [] if $depth >= $MAX_PLIES;

    my $query_play = @$history_uci ? join(",", @$history_uci) : "";
    my $r = explorer(play => $query_play, moves => 5, topGames => 0, recentGames => 0);

    my $total = ($r->{white} // 0) + ($r->{draws} // 0) + ($r->{black} // 0);
    return [] if $total < $MIN_GAMES;

    my $moves = $r->{moves} // [];
    return [] unless @$moves;

    my $top = $moves->[0];
    my $san = $top->{san};
    my $uci = $top->{uci};

    my $ann = undef;
    if (my $a = $annots->{"$opening_name/$depth"}) {
        $ann = $a->{text} if $a->{san} eq $san;
    }

    my $ply = { san => $san, uci => $uci, annotation => $ann, alternativeSans => [] };
    my $rest = walk_line($opening_name, [@$history_uci, $uci], $depth + 1);
    return [$ply, @$rest];
}

sub build_opening {
    my ($o) = @_;

    logmsg("opening: $o->{name} (eco $o->{eco}, $o->{side}, target lineCount=$o->{lineCount})");

    my @history_uci;
    for my $san (@{$o->{rootSan}}) {
        my $query_play = @history_uci ? join(",", @history_uci) : "";
        my $r = explorer(play => $query_play, moves => 12, topGames => 0, recentGames => 0);
        my ($m) = grep { $_->{san} eq $san } @{$r->{moves} // []};
        die "root san '$san' not found in explorer moves for opening '$o->{name}'" unless $m;
        push @history_uci, $m->{uci};
    }

    my $query_play = join(",", @history_uci);
    my $r = explorer(play => $query_play, moves => 12, topGames => 0, recentGames => 0);
    my @candidates = @{$r->{moves} // []};
    splice(@candidates, $o->{lineCount}) if @candidates > $o->{lineCount};

    logmsg("  got " . scalar(@candidates) . " candidate line(s) for $o->{name}");

    my @lines;
    for my $c (@candidates) {
        my $line_name  = $c->{san};
        logmsg("  walking line '$line_name' for $o->{name}");
        my @line_history = (@history_uci, $c->{uci});
        my $rest = walk_line($o->{name}, \@line_history, scalar @{$o->{rootSan}} + 1);
        my $root_plies = [ map { { san => $_, uci => "", annotation => undef, alternativeSans => [] } } @{$o->{rootSan}} ];
        my $candidate_ply = { san => $c->{san}, uci => $c->{uci}, annotation => undef, alternativeSans => [] };
        my $total_plies = scalar(@$root_plies) + 1 + scalar(@$rest);
        logmsg("  line '$line_name' total plies=$total_plies");
        push @lines, {
            name => $line_name,
            plies => [@$root_plies, $candidate_ply, @$rest],
            tags => [],
        };
    }

    for my $l (@lines) {
        for my $i (0 .. $#{$o->{rootSan}}) {
            $l->{plies}[$i]{uci} = $history_uci[$i];
        }
    }

    return {
        name        => $o->{name},
        eco         => $o->{eco},
        side        => $o->{side},
        rootFen     => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        description => undef,
        isSeed      => \1,
        lines       => \@lines,
    };
}

my $total_openings = scalar @{$cat->{openings}};
my $idx = 0;
my @openings = map {
    $idx++;
    logmsg("[$idx/$total_openings] building $_->{name}");
    build_opening($_);
} @{$cat->{openings}};
my $out = { version => 1, openings => \@openings };

open my $oh, ">", $OUT_PATH or die "write $OUT_PATH: $!";
print $oh JSON::XS->new->canonical->pretty->encode($out);
close $oh;

logmsg("wrote $OUT_PATH with " . scalar(@openings) . " openings");
logmsg("explorer requests total=$req_count cache_hits=$cache_hits cache_miss=$cache_miss");
logmsg("build-seed.pl done");
close $LOG;
print "wrote $OUT_PATH with ", scalar @openings, " openings\n";
