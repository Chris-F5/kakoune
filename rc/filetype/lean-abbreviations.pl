#!/usr/bin/env perl

use strict;
use warnings;
use JSON;

binmode STDOUT, ":encoding(UTF-8)";


sub single_quote {
    my $token = shift;
    $token =~ s/'/''/g;
    return "'$token'";
}
sub double_quote {
    my $token = shift;
    $token =~ s/"/""/g;
    return "\"$token\"";
}
sub escape_regex {
    my $token = shift;
    $token =~ s/([\\^\$.*+?\[\]{}|()])/\\$1/g;
    return $token
}


if (@ARGV != 1) {
    die "Usage: $0 <json_file>\n";
}

my $file_path = $ARGV[0];

my $json_text = do {
    open(my $json_fh, "<", $file_path)
        or die("Can't open \"$file_path\": $!\n");
    local $/;
    <$json_fh>
};

my $data = decode_json($json_text);

my @keys = keys %$data;
my @escaped_keys = map { escape_regex($_) } @keys;

# A regex matching any abbreviation.
my $abbreviation_full_regex = '\\\\(' . join('|', @escaped_keys) . ')';

my @sorted_keys = sort { length($b) <=> length($a) } @keys;

my @final_regex_parts;
for my $key (@sorted_keys) {
    my @longer_keys = grep { $_ ne $key and index($_, $key) == 0 } @keys;

    if (@longer_keys) {
        my %next_chars;
        for my $longer_key (@longer_keys) {
            my $next_char = substr($longer_key, length($key), 1);
            $next_chars{$next_char} = 1;
        }
        my @lookaheads = map { '(?!' . escape_regex($_) . ')' } keys %next_chars;
        my $lookahead = join('', @lookaheads);
        push @final_regex_parts, escape_regex($key) . $lookahead;
    } else {
        push @final_regex_parts, escape_regex($key);
    }
}

# An abbreviation followed by another character such that the full string is
# not a prefix of any abbreviations.
my $abbreviation_terminated_regex = '(\\\\(' . join('|', @final_regex_parts) . '))?.';

print "set-option global lean_abbreviation_full_regex " . single_quote($abbreviation_full_regex);
print "\n";
print "set-option global lean_abbreviation_terminated_regex " . single_quote($abbreviation_terminated_regex);
print "\n";

my @substitute_try_blocks;
while (my ($key, $value) = each %$data) {
    my $block
        = "set-register / " . single_quote('\A\\\\' . escape_regex($key) . '\z') . "\n"
        . "execute-keys '<a-k><ret>'" . "\n"
        . "set-register \\\" " . single_quote($value) . "\n";
    push @substitute_try_blocks, $block;
}
my $substitute_command
  = "try "
  . join(" catch ", map { single_quote($_) } @substitute_try_blocks) . "\n"
  . "execute-keys R" . "\n";
print "set-option global lean_abbreviation_substitute_command " . single_quote($substitute_command);
print "\n";
