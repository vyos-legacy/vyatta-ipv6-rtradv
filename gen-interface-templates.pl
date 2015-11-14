#!/usr/bin/perl
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
# Portions created by Vyatta are Copyright (C) 2009 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Bob Gilligan
# Date: August 2009
# Description: Script to automatically generate per-interface templates
#              for IPv6 Router Advertisements
#
# **** End License ****

use strict;
use warnings;

# set DEBUG in environment to test script
my $debug = $ENV{'DEBUG'};

# Mapping from configuration level to ifname used AT THAT LEVEL
# Priority values are taken from the relevant node, any changes to those need to be reflected here.
my %interface_hash = (
    'loopback/node.tag'                             => {'if_name' => '$VAR(@)', 'priority' => '300'},
    'ethernet/node.tag'                             => {'if_name' => '$VAR(@)', 'priority' => '318'},
    'ethernet/node.tag/pppoe/node.tag'              => {'if_name' => 'pppoe$VAR(@)', 'priority' => '319'},
    'ethernet/node.tag/vif/node.tag'                => {'if_name' => '$VAR(../@).$VAR(@)', 'priority' => '319'},
    'ethernet/node.tag/vif/node.tag/pppoe/node.tag' => {'if_name' => 'pppoe$VAR(@)', 'priority' => '320'},
    'bonding/node.tag'                              => {'if_name' => '$VAR(@)', 'priority' => '315'},
    'bonding/node.tag/vif/node.tag'                 => {'if_name' => '$VAR(../@).$VAR(@)', 'priority' => '320'},
    'tunnel/node.tag'                               => {'if_name' => '$VAR(@)', 'priority' => '380'},
    'wireless/node.tag'                             => {'if_name' => '$VAR(@)', 'priority' => '318'},
    'wireless/node.tag/vif/node.tag'                => {'if_name' => '$VAR(../@).$VAR(@)', 'priority' => '322'},
    'pseudo-ethernet/node.tag'                      => {'if_name' => '$VAR(@)', 'priority' => '319'},
    'bridge/node.tag'                               => {'if_name' => '$VAR(@)', 'priority' => '310'},
    'openvpn/node.tag'                              => {'if_name' => '$VAR(@)', 'priority' => '460'},
    'wirelessmodem/node.tag'                        => {'if_name' => '$VAR(@)', 'priority' => '350'},
    'l2tpv3/node.tag'                               => {'if_name' => '$VAR(@)', 'priority' => '460'},
    'vxlan/node.tag'                                => {'if_name' => '$VAR(@)', 'priority' => '460'},
);

sub gen_template {
    my ($inpath, $outpath, $ifname, $priority) = @_;

    print $outpath, "\n" if ($debug);
    opendir my $d, $inpath
        or die "Can't open: $inpath:$!";

    # walk through sample templates
    foreach my $name (grep {!/^\./} readdir $d) {

        my $in  = "$inpath/$name";
        my $out = "$outpath/$name";

        # recurse into subdirectory
        if (-d $in) {
            my $subif = $ifname;
            $subif =~ s#@\)#../@)#g if ($name ne 'node.tag');

            (-d $out)
                or mkdir($out)
                or die "Can't create $out: $!";

            gen_template($in, $out, $subif, $priority);
            next;
        }

        print "in: $in out: $out\n" if ($debug);
        open my $inf,  '<', $in  or die "Can't open $in: $!";
        open my $outf, '>', $out or die "Can't open $out: $!";

        if ($out =~ /autoconf/) {
            $priority += 2;
        } elsif ( $out =~ /disable-forwarding/) {
            $priority += 1;
        }

        while (my $line = <$inf>) {
            $line =~ s#\$PRIORITY#$priority#;
            $line =~ s#\$IFNAME#$ifname#;
            print $outf $line;
        }
        close $inf;
        close $outf or die "Close error $out:$!";
    }
    closedir $d;
}

sub mkdir_p {
    my $path = shift;

    return 1 if (mkdir($path));

    my $pos = rindex($path, "/");
    return unless $pos != -1;
    return unless mkdir_p(substr($path, 0, $pos));
    return mkdir($path);
}

die "Usage: $0 output_directory\n" if ($#ARGV < 0);

my $outdir = $ARGV[0];

foreach my $if_tree (keys %interface_hash) {
    my $inpath  = "interface-templates";
    my $outpath = "$outdir/interfaces/$if_tree";
    (-d $outpath)
        or mkdir_p($outpath)
        or die "Can't create $outpath:$!";

    gen_template($inpath, $outpath, $interface_hash{$if_tree}{'if_name'}, $interface_hash{$if_tree}{'priority'});
}

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
