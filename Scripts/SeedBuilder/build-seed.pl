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
my $MIN_PLIES = 10;

my %SOURCES = (
    masters => {
        api            => "https://explorer.lichess.ovh/masters",
        min_games      => 50,
        min_games_soft => 5,
        extra_params   => {},
    },
    open => {
        api            => "https://explorer.lichess.ovh/lichess",
        min_games      => 500,
        min_games_soft => 50,
        extra_params   => {
            ratings => "2200,2500",
            speeds  => "blitz,rapid,classical",
        },
    },
);

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
    my ($source, %q) = @_;
    $req_count++;
    my $cfg = $SOURCES{$source} or die "unknown source '$source'";
    my %merged = (%q, %{ $cfg->{extra_params} });
    # masters uses empty prefix to preserve pre-dual-source cache entries; do not change.
    my $prefix = $source eq "masters" ? "" : "$source|";
    my $key  = md5_hex($prefix . join("|", map { "$_=$merged{$_}" } sort keys %merged));
    my $file = "$CACHE_DIR/$key.json";
    my $play_preview = $merged{play} // "";
    $play_preview = substr($play_preview, 0, 60) . "..." if length($play_preview) > 60;
    if (-e $file) {
        $cache_hits++;
        logmsg("  explorer[$source] #$req_count CACHE play=[$play_preview]");
        open my $fh, "<", $file; local $/; return decode_json(scalar <$fh>);
    }
    $cache_miss++;
    my $url = $cfg->{api} . "?" . join("&", map { "$_=$merged{$_}" } sort keys %merged);
    logmsg("  explorer[$source] #$req_count FETCH play=[$play_preview]");
    sleep(1);
    my %opts;
    $opts{headers} = { Authorization => $AUTH_HEADER } if $AUTH_HEADER;
    my $res;
    my $attempt = 0;
    while (1) {
        $res = $http->get($url, \%opts);
        last if $res->{success};
        my $retryable = $res->{status} == 429
                      || ($res->{status} >= 500 && $res->{status} <= 599);
        if ($retryable && $attempt < 5) {
            my $wait = 2 ** $attempt;
            logmsg("  explorer[$source] #$req_count got $res->{status} $res->{reason}, retrying in ${wait}s (attempt " . ($attempt + 1) . "/5)");
            sleep($wait);
            $attempt++;
            next;
        }
        die "explorer $url: $res->{status} $res->{reason}";
    }
    open my $fh, ">", $file; print $fh $res->{content}; close $fh;
    decode_json($res->{content});
}

sub walk_line {
    my ($source, $opening_name, $history_uci, $depth) = @_;
    return ([], undef) if $depth >= $MAX_PLIES;
    my $cfg = $SOURCES{$source};

    my $query_play = @$history_uci ? join(",", @$history_uci) : "";
    my $r = explorer($source, play => $query_play, moves => 5, topGames => 0, recentGames => 0);

    # Lichess Explorer attaches an `opening` object to every response
    # carrying the canonical ECO + name for the queried position. The
    # deepest non-null name we see while walking is the most-specific
    # named variation reached — that's what we use as the line label.
    my $own_named = $r->{opening}{name};

    my $total = ($r->{white} // 0) + ($r->{draws} // 0) + ($r->{black} // 0);
    my $threshold = $depth < $MIN_PLIES ? $cfg->{min_games_soft} : $cfg->{min_games};
    return ([], $own_named) if $total < $threshold;

    my $moves = $r->{moves} // [];
    return ([], $own_named) unless @$moves;

    my $top = $moves->[0];
    my $san = $top->{san};
    my $uci = $top->{uci};

    my $ann = undef;
    if (my $a = $annots->{"$opening_name/$depth"}) {
        $ann = $a->{text} if $a->{san} eq $san;
    }

    my $ply = { san => $san, uci => $uci, annotation => $ann, alternativeSans => [] };
    my ($rest, $deeper_named) = walk_line($source, $opening_name, [@$history_uci, $uci], $depth + 1);
    return ([$ply, @$rest], $deeper_named // $own_named);
}

sub build_opening {
    my ($o) = @_;

    logmsg("opening: $o->{name} (eco $o->{eco}, $o->{side}, target lineCount=$o->{lineCount})");

    my @all_lines;
    for my $source (qw(masters open)) {
        logmsg("  [source=$source] resolving root line");
        my @history_uci;
        for my $san (@{$o->{rootSan}}) {
            my $query_play = @history_uci ? join(",", @history_uci) : "";
            my $r = explorer($source, play => $query_play, moves => 12, topGames => 0, recentGames => 0);
            my ($m) = grep { $_->{san} eq $san } @{$r->{moves} // []};
            die "root san '$san' not found in explorer[$source] moves for opening '$o->{name}'" unless $m;
            push @history_uci, $m->{uci};
        }

        my $query_play = join(",", @history_uci);
        my $r = explorer($source, play => $query_play, moves => 12, topGames => 0, recentGames => 0);
        my @candidates = @{$r->{moves} // []};
        splice(@candidates, $o->{lineCount}) if @candidates > $o->{lineCount};

        logmsg("  [source=$source] got " . scalar(@candidates) . " candidate line(s) for $o->{name}");

        my @pending;
        for my $c (@candidates) {
            my @line_history = (@history_uci, $c->{uci});
            my ($rest, $walk_named) = walk_line($source, $o->{name}, \@line_history, scalar @{$o->{rootSan}} + 1);
            # Name priority chain:
            #   1. catalogue `variationNames` override (explicit human label)
            #   2. deepest Lichess Explorer `opening.name` seen on the walk
            #   3. candidate SAN as a final fallback
            # The Lichess name is the verifiable default — anyone can
            # replay the same play sequence and check the returned
            # opening field. The catalogue override is only needed when
            # the API name is missing or unclear.
            my $vmap = $o->{variationNames} // {};
            my $line_name = $vmap->{$c->{san}} // $walk_named // $c->{san};
            push @pending, { c => $c, rest => $rest, line_name => $line_name };
        }

        # Disambiguate same-named candidates (e.g. two different fork
        # SANs both classifying to the same Lichess opening). Suffix the
        # fork SAN onto each colliding name so the UI can tell them
        # apart. Singletons get the API name unchanged.
        my %name_count;
        $name_count{$_->{line_name}}++ for @pending;
        for my $p (@pending) {
            if ($name_count{$p->{line_name}} > 1) {
                $p->{line_name} = "$p->{line_name} ($p->{c}{san})";
            }
        }

        for my $p (@pending) {
            my ($c, $rest, $line_name) = ($p->{c}, $p->{rest}, $p->{line_name});
            logmsg("  [source=$source] walking line '$line_name' for $o->{name}");
            my $root_plies = [ map { { san => $_, uci => "", annotation => undef, alternativeSans => [] } } @{$o->{rootSan}} ];
            for my $i (0 .. $#{$o->{rootSan}}) {
                $root_plies->[$i]{uci} = $history_uci[$i];
            }
            my $candidate_ply = { san => $c->{san}, uci => $c->{uci}, annotation => undef, alternativeSans => [] };
            my $total_plies = scalar(@$root_plies) + 1 + scalar(@$rest);
            logmsg("  [source=$source] line '$line_name' total plies=$total_plies");
            # Stable identity that survives renames, walk shifts, and
            # variation-name overrides. Pinned to the fork move's UCI
            # (deterministic across runs) plus the opening / source so
            # `SeedLoader` can upsert and preserve attached `LineProgress`
            # across seed version bumps.
            my $stable_key = join("|", $o->{name}, $source, $c->{uci});
            push @all_lines, {
                name      => $line_name,
                plies     => [@$root_plies, $candidate_ply, @$rest],
                tags      => [],
                source    => $source,
                stableKey => $stable_key,
            };
        }
    }

    return {
        name        => $o->{name},
        eco         => $o->{eco},
        side        => $o->{side},
        rootFen     => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        description => undef,
        isSeed      => \1,
        lines       => \@all_lines,
    };
}

my $total_openings = scalar @{$cat->{openings}};
my $idx = 0;
my @openings = map {
    $idx++;
    logmsg("[$idx/$total_openings] building $_->{name}");
    build_opening($_);
} @{$cat->{openings}};
my $out = { version => 4, openings => \@openings };

my $tmp_path = "$OUT_PATH.tmp";
open my $oh, ">", $tmp_path or die "write $tmp_path: $!";
# Force the encoder into UTF-8 byte-output mode AND open the file
# handle in raw mode so the bytes pass through verbatim. Without
# this, non-ASCII opening names (e.g. "Sörensen Defense") landed as
# single Latin-1 bytes (0xf6) instead of valid UTF-8 (0xc3 0xb6),
# breaking jq + the iOS JSONDecoder on input.
binmode $oh, ':raw';
print $oh JSON::XS->new->utf8(1)->canonical->pretty->encode($out);
close $oh;
rename $tmp_path, $OUT_PATH or die "rename $tmp_path -> $OUT_PATH: $!";

logmsg("wrote $OUT_PATH with " . scalar(@openings) . " openings");
logmsg("explorer requests total=$req_count cache_hits=$cache_hits cache_miss=$cache_miss");
logmsg("build-seed.pl done");
close $LOG;
print "wrote $OUT_PATH with ", scalar @openings, " openings\n";
