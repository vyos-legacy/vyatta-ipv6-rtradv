#!/usr/bin/perl
#
# Module: vyatta-ipv6-eui64pl
#
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2005-2009 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Bob Gilligan <gilligan@vyatta.com>
# Date: October 2009
# Description:  Configure an interface with an IPv6 address based on the
#               EUI-64 format.
#
# **** End License ****
#
#

#
# Syntax:
#    vyatta-ipv6-eui64.pl --create <ifname> <IPv6-prefix>
#    vyatta-ipv6-eui64.pl --delete <ifname> <IPv6-prefix>
#
# The first form will create a new IPv6 address on <ifname> using
# the EUI-64 format.  The <IPv6-prefix> will be used to form the
# high-order 64 bits of the address.  The 48-bit MAC address will
# be padded out as specified in RFC-3513 to form a 64-bit EUI-64
# which will be used to form the low-order 64-bits of the address.
#
# The second form removes an EUI-64 format address from <ifname>.
# First an IPv6 address will be formed in the same manner as above.  Then,
# if that address is assigned to <ifname>, it will be deleted.
#

use strict;
use lib "/opt/vyatta/share/perl5/";

use Vyatta::Config;
use Vyatta::TypeChecker;
use Getopt::Long;

# Set to 1 to enable debug output
my $debug_flag=0;

# Hash to complement the second U/L bit:
my %ul_hash = ( '0' => '2',
                '1' => '3',
                '2' => '0',
                '3' => '1',
                '4' => '6',
                '5' => '7',
                '6' => '4',
                '7' => '5',
                '8' => 'a',
                '9' => 'b',
                'a' => '8',
                'b' => '9',
                'c' => 'e',
                'd' => 'f',
                'e' => 'c',
                'f' => 'd' );

sub log_msg {
    my $message = shift;

    if ($debug_flag > 0) {
        print "DEBUG: $message"
    }
}

my @create;
my @delete;

GetOptions("create=s{2}"       => \@create,
           "delete=s{2}"       => \@delete,
           "debug"             => \$debug_flag
);

if (scalar(@create) == 2) {
    create_addr(@create);
    exit 0;
}


if (scalar(@delete)) {
    delete_addr(@delete);
    exit 0;
}

printf("Error: invalid args: $ARGV\n");
exit 1;

# Put an IPv6 addr in canonical format without "::"
sub canonicalize_addr {
    my $compressed_addr = $_;
    my $num_colons;
    
    my $addr_colons = $compressed_addr;
    $addr_colons =~ s/[0-9a-fA-F]*//g;
    my $num_colons = length $addr_colons;
    log_msg("num_colons = $num_colons\n");

    my $addr_str = ":0:";
    for ( ; $num_colons < 7 ; $num_colons++) {
        $addr_str .= "0:";
    }

    # Add trailing zero if compression is at end of address
    if ($compressed_addr =~m /::$/) {
        $addr_str .= "0";
    }
    
    my $canonical_addr = $compressed_addr;
    $canonical_addr =~ s/::/$addr_str/;
    log_msg("canonical_addr = $canonical_addr\n");
    return $canonical_addr;
}

sub validate_and_form_addr {
    my $ifname = $_[0];
    my $prefix = $_[1];

    # Validate ifname

    # We expect the interface to exist and to be configured for IPv6
    if (! -d "/proc/sys/net/ipv6/conf/$ifname") {
        printf("Error: Interface $ifname does not exist.\n");
        return undef;
    }
    
    # Validate prefix
    if (! validateType('ipv6net', $prefix)) {
        printf("Error: $prefix is not a valid IPv6 prefix.\n");
        return undef;
    }
    my $prefix_len = $prefix;
    $prefix_len =~ s/^(.*)\///;         # Shave off address part
    if ($prefix_len != 64) {
        printf("Error: Prefix lenght is $prefix_len.  It must be 64.\n");
        return undef;
    }

    # Get 48-bit MAC addr of $ifname

    my $macaddr = `ip link show $ifname | grep link/ether | awk '{print \$2}'`;
    $macaddr =~ s/\n//;

    log_msg("macaddr = $macaddr\n");

    if (!validateType('macaddr', $macaddr)) {
        printf("Error: Couldn't get MAC addr for $ifname\n");
        return undef;
    }
    
    # Form 64-bit Modified EUI-64 based on 48-bit MAC addr

    $macaddr =~ m/(..):(..):(..):(..):(..):(..)/;
    log_msg("1 = $1 2 = $2 3 = $3 4 = $4 5 = $5 6 = $6\n");

    my $byte_1 = $1;
    my $byte_2 = $2;
    my $byte_3 = $3;
    my $byte_4 = $4;
    my $byte_5 = $5;
    my $byte_6 = $6;

    $byte_1 =~ m/([0-9a-fA-F])([0-9a-fA-F])/;
    my $nibble_1 = $1;
    my $nibble_2 = $2;

    log_msg("n1 = $nibble_1 n2 = $nibble_2\n");

    # Complement bit-2 of second nibble to change U bit to L
    $nibble_2 = $ul_hash{$nibble_2};

    log_msg("n1 = $nibble_1 n2 = $nibble_2\n");

    my $eui64 = $nibble_1 . $nibble_2 . $byte_2 . ":" . $byte_3 . "ff:fe" . $byte_4 . ":" . $byte_5 . $byte_6;

    log_msg("eui64 = $eui64\n");

    # Form 128-bit IPv6 addr based on $prefix and EUI-64
    my $ipv6_addr = $prefix;
    $ipv6_addr =~ s/\/.*//;      # Strip off the trailing prefix len

    log_msg("ipv6_addr = $ipv6_addr\n");

    $ipv6_addr = canonicalize_addr($ipv6_addr);

    log_msg("ipv6_addr = $ipv6_addr\n");

    # strip off the low-order 64-bits, but leave the trailing colon
    $ipv6_addr =~ s/[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F]*$//;

    log_msg("ipv6_addr = $ipv6_addr\n");

    $ipv6_addr = $ipv6_addr . $eui64;

    log_msg("ipv6_addr = $ipv6_addr\n");

    # Add prefix len to addr
    $ipv6_addr = "$ipv6_addr/64";

    log_msg("ipv6_addr = $ipv6_addr\n");

    return $ipv6_addr;
}

sub create_addr {
    my $ifname = $_[0];
    my $prefix = $_[1];

    my $ipv6_addr = validate_and_form_addr($ifname, $prefix);
    if (! defined($ipv6_addr)) {
        exit 1;
    }
    
    # Check to see if 128-bit addr is already assigned to any interface - XXX

    # Assign addr to $ifname
    my $retval = system("ip -6 addr add $ipv6_addr dev $ifname");

    if ($retval != 0) {
        printf("Error: Couldn't assign IPv6 addr $ipv6_addr to $ifname\n");
        exit 1;
    }
}

sub delete_addr {
    my $ifname = $_[0];
    my $prefix = $_[1];

    my $ipv6_addr = validate_and_form_addr($ifname, $prefix);
    if (! defined($ipv6_addr)) {
        exit 1;
    }
    
    # Attempt to delete addr from $ifname...
    my $retval = system("ip -6 addr del $ipv6_addr dev $ifname");
    if ($retval != 0) {
        printf("Warning: Couldn't delete IPv6 addr $ipv6_addr from $ifname\n");
    }
}

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
