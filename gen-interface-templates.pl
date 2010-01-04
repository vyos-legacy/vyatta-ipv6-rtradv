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
my %interface_hash = (
    'loopback/node.tag'                             => '$VAR(@)',
    'ethernet/node.tag'                             => '$VAR(@)',
    'ethernet/node.tag/pppoe/node.tag'              => 'pppoe$VAR(@)',
    'ethernet/node.tag/vif/node.tag'                => '$VAR(../@).$VAR(@)',
    'ethernet/node.tag/vif/node.tag/pppoe/node.tag' => 'pppoe$VAR(@)',
    'bonding/node.tag'                              => '$VAR(@)',
    'bonding/node.tag/vif/node.tag'                 => '$VAR(../@).$VAR(@)',
    'tunnel/node.tag'                               => '$VAR(@)',
    'bridge/node.tag'                               => '$VAR(@)',
    'openvpn/node.tag'                              => '$VAR(@)',
    'wirelessmodem/node.tag'                        => '$VAR(@)',
    'multilink/node.tag/vif/node.tag'               => '$VAR(../@)',

    'adsl/node.tag/pvc/node.tag/bridged-ethernet' => '$VAR(../../@)',
    'adsl/node.tag/pvc/node.tag/classical-ipoa'   => '$VAR(../../@)',
    'adsl/node.tag/pvc/node.tag/pppoa/node.tag'   => '$VAR(../../@)',
    'adsl/node.tag/pvc/node.tag/pppoe/node.tag'   => '$VAR(../../@)',

    'serial/node.tag/cisco-hdlc/vif/node.tag'  => '$VAR(../../@).$VAR(@)',
    'serial/node.tag/frame-relay/vif/node.tag' => '$VAR(../../@).$VAR(@)',
    'serial/node.tag/ppp/vif/node.tag'         => '$VAR(../../@).$VAR(@)',
);


# Mapping from configuration level to config path string AT THAT LEVEL
my %config_path_hash = (
    'loopback/node.tag'                             => 
	'interfaces loopback $VAR(@)',
    'ethernet/node.tag'                             => 
	'interfaces ethernet $VAR(@)',
    'ethernet/node.tag/pppoe/node.tag'              => 
	'interfaces ethernet $VAR(../@) pppoe VAR(@)',
    'ethernet/node.tag/vif/node.tag'                => 
	'interfaces ethernet $VAR(../@) vif $VAR(@)',
    'ethernet/node.tag/vif/node.tag/pppoe/node.tag' => 
	'interfaces ethernet $VAR(../../@) vif $VAR(../@) pppoe $VAR(@)',
    'bonding/node.tag'                              => 
	'interfaces bonding $VAR(@)',
    'bonding/node.tag/vif/node.tag'                 => 
	'interfaces bonding $VAR(../@) vif $VAR(@)',
    'tunnel/node.tag'                               => 
	'interfaces tunnel $VAR(@)',
    'bridge/node.tag'                               => 
	'interfaces bridge $VAR(@)',
    'openvpn/node.tag'                              => 
	'interfaces openvpn $VAR(@)',
    'wirelessmodem/node.tag'                        => 
	'interfaces wirelessmodem $VAR(@)',
    'multilink/node.tag/vif/node.tag'               => 
	'interfaces multilink $VAR(../@) vif $VAR(@)',

    'adsl/node.tag/pvc/node.tag/bridged-ethernet' => 
	'interfaces adsl $VAR(../../@) pvc $VAR(../@) bridged-ethernet',
    'adsl/node.tag/pvc/node.tag/classical-ipoa'   => 
	'interfaces adsl $VAR(../../@) pvc $VAR(../@) classical-ipoa',
    'adsl/node.tag/pvc/node.tag/pppoa/node.tag'   => 
	'interfaces adsl $VAR(../../@) pvc $VAR(../@) pppoa $VAR(@)',
    'adsl/node.tag/pvc/node.tag/pppoe/node.tag'   => 
	'interfaces adsl $VAR(../../@) pvc $VAR(../@) pppoe $VAR(@)',

    'serial/node.tag/cisco-hdlc/vif/node.tag'  => 
	'interfaces serial $VAR(../../@) cisco-hdlc vif $VAR(@)',
    'serial/node.tag/frame-relay/vif/node.tag' => 
	'interfaces serial $VAR(../../@) frame-relay vif $VAR(@)',
    'serial/node.tag/ppp/vif/node.tag'         => 
	'interfaces serial $VAR(../../@) ppp vif $VAR(@)',
);


sub gen_template {
    my ( $inpath, $outpath, $ifname, $config_path ) = @_;
    
    print $outpath, "\n" if ($debug);
    opendir my $d, $inpath
      or die "Can't open: $inpath:$!";

    # walk through sample templates
    foreach my $name ( grep { !/^\./ } readdir $d ) {
        
        my $in  = "$inpath/$name";
        my $out = "$outpath/$name";

	# recurse into subdirectory
        if ( -d $in ) {
            my $subif = $ifname;
            $subif =~ s#@\)#../@)#g if ($name ne 'node.tag');

            my $sub_config_path = $config_path;
            $sub_config_path =~ s#@\)#../@)#g if ($name ne 'node.tag');

            ( -d $out )
              or mkdir($out)
              or die "Can't create $out: $!";

            gen_template( $in, $out, $subif, $sub_config_path );
            next;
        }

        print "in: $in out: $out\n" if ($debug);
        open my $inf,  '<', $in  or die "Can't open $in: $!";
        open my $outf, '>', $out or die "Can't open $out: $!";

        while ( my $line = <$inf> ) {
            $line =~ s#\$IFNAME#$ifname#;
            $line =~ s#\$CONFIG_PATH#$config_path#;
            print $outf $line;
        }
        close $inf;
        close $outf or die "Close error $out:$!";
    }
    closedir $d;
}

sub mkdir_p {
    my $path = shift;

    return 1 if ( mkdir($path) );

    my $pos = rindex( $path, "/" );
    return unless $pos != -1;
    return unless mkdir_p( substr( $path, 0, $pos ) );
    return mkdir($path);
}

die "Usage: $0 output_directory\n" if ($#ARGV < 0);

my $outdir = $ARGV[0];

foreach my $if_tree ( keys %interface_hash ) {
    my $inpath  = "interface-templates";
    my $outpath = "$outdir/interfaces/$if_tree";
    ( -d $outpath )
      or mkdir_p($outpath)
      or die "Can't create $outpath:$!";

    gen_template( $inpath, $outpath, $interface_hash{$if_tree}, 
		  $config_path_hash{$if_tree});
}

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
