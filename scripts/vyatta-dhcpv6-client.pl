#!/usr/bin/perl
#
# Module: vyatta-dhcpv6-client.pl
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
# Date: 2010
# Description: Start and stop DHCPv6 client daemon for an interface.
#
# **** End License ****
#
#

use strict;
use lib "/opt/vyatta/share/perl5/";
use FileHandle;
use Vyatta::Config;
use Getopt::Long;

my $start_flag;
my $stop_flag;
my $temp_flag;
my $params_only_flag;
my $ifname;


#
# Main Section
#

GetOptions("start" => \$start_flag,
	   "stop" => \$stop_flag,
	   "temporary" => \$temp_flag,
	   "parameters-only" => \$params_only_flag,
	   "ifname=s" => \$ifname,
    );

if ((defined $temp_flag) && (defined $params_only_flag)) {
    printf("Error: --temporary and --parameters-only flags are mutually exclusive.\n");
    exit 1;
}

my $pidfile = "/var/lib/dhcp3/dhclient_v6_$ifname.pid";

if (defined $stop_flag) {
    # Stop dhclient -6 on $ifname

    printf("Stopping daemon...\n");
    my $output=`dhclient -6 -nw -x -pf $pidfile $ifname`;
    printf($output);
}

if (defined $start_flag) {
    # start "dhclient -6" on $ifname

    my $args = "-6 -nw";
    $args .= " -cf /var/lib/dhcp3/dhclient_v6_$ifname.conf";
    $args .= " -pf $pidfile";
    $args .= " -lf /var/lib/dhcp3/dhclient_v6_$ifname.leases";

    if (defined $temp_flag) {
	$args .= " -T";
    }
    if (defined $params_only_flag) {
	$args .= " -S";
    }

    printf("Starting daemon...\n");
    my $output=`dhclient $args $ifname`;
    printf($output);
}
