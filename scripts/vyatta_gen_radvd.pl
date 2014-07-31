#!/usr/bin/perl
#
# Module: vyatta_gen_radvd.pl
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
# Date: 2009
# Description:  Setup section of the radvd.conf file for an interface.
#
# **** End License ****
#
#

#
# Syntax:
#    vyatta_gen_radvd.pl --generate <ifname>
#    vyatta_gen_radvd.pl --delete <ifname>
#
# In the first instance, <ifname> is the name of the interface for
# which the configuration file is to be generated (e.g. eth0, eth7.3,
# pppoe7, wan0.1, ml0, etc.) and <config-param-root> is the root of
# the tree of configuration parameters
# (e.g. "/interfaces/ethernet/eth0/ipv6/router-advert").
#
# This script generates a partial radvd.conf file holding the
# parameters for one interface, and writes it to a temp file.  It then
# strips any previous configuration for this interface from the
# system-wide config file /etc/radvd.conf.  Then it cat's the contents
# of the temp file into the system-wide config file /etc/radvd.conf.
# After that it re-starts the radvd daemon.  Since the daemon is stateless,
# re-starting it is a lightweight operation.
#
# In the second instance, <ifname> is the name of the interface
# whose configuration is to be removed from the /etc/radvd.conf file

use strict;
use lib "/opt/vyatta/share/perl5/";

use Vyatta::Config;
use Getopt::Long;
use Vyatta::Interface;

my $conf_file="/etc/radvd.conf";

# Set to 1 to enable debug output
my $debug_flag=0;

sub log_msg {
    my $message = shift;

    if ($debug_flag > 0) {
        print "DEBUG: $message"
    }
}

my $config;
my $FD_WR;      # Temporary config file pointer
my $generate;
my $delete;

GetOptions("generate=s"       => \$generate,
           "delete=s"         => \$delete
);

if ($generate) {
    generate_conf($generate);
    exit 0;
}

if ($delete) {
    delete_conf($delete);
    exit 0;
}

printf("Error: invalid args: $ARGV\n");
exit 1;

# Parse and write config file for one prefix under an interface
sub do_prefix {
    my ($param_root, $prefix) = @_;

    # RFC-4861 parameters for each element of AdvPrefixList.
    # Parameters with fixed default values have those values specified
    # here.  Those values may be simply over-ridden by user-selected
    # values.  Parameters that have algorithmic default values have
    # their value set to -1 here.  User-selected values can over-ride
    # them.  If the user doesn't select a value, a final value is
    # determined later on.  Note: Keys are the parameter strins
    # used in radvd.conf file, which do not always match exactly the
    # strings used in RFC-4861.

    my %prefix_param_hash = ( 'AdvValidLifetime' => '2592000',
                              'AdvOnLink' => 'on',
                              'AdvPreferredLifetime' => '-1',
                              'AdvAutonomous' => 'on' );

    my @prefix_params = $config->listNodes("$param_root prefix $prefix");
    log_msg("prefix_params for prefix $prefix: @prefix_params\n");

    # Read in parameters set by user
    foreach my $prefix_param (@prefix_params) {
        log_msg("prefix_param = $prefix_param\n");

        my $value = 
            $config->returnValue("$param_root prefix $prefix $prefix_param");

        if ($prefix_param eq "on-link-flag") {
            if ($value eq "true") {
                $prefix_param_hash{'AdvOnLink'} = 'on';
            } else {
                $prefix_param_hash{'AdvOnLink'} = 'off';
            }
        } elsif ($prefix_param eq "autonomous-flag") {
            if ($value eq "true") {
                $prefix_param_hash{'AdvAutonomous'} = 'on';
            } else {
                $prefix_param_hash{'AdvAutonomous'} = 'off';
            }
        } elsif ($prefix_param eq "valid-lifetime") {
            $prefix_param_hash{'AdvValidLifetime'} = $value;
        } elsif ($prefix_param eq "preferred-lifetime") {
            $prefix_param_hash{'AdvPreferredLifetime'} = $value;
        }
        
    }

    # Fill in any missing default values
    if ($prefix_param_hash{'AdvPreferredLifetime'} == -1) {
        if (($prefix_param_hash{'AdvValidLifetime'} > 604800) ||
            ($prefix_param_hash{'AdvValidLifetime'} eq "infinity")) {
            $prefix_param_hash{'AdvPreferredLifetime'} = 604800;
        } else {
            $prefix_param_hash{'AdvPreferredLifetime'} = 
                $prefix_param_hash{'AdvValidLifetime'};
        }
    }

    # Validate user parameters
    if (($prefix_param_hash{'AdvValidLifetime'} ne "infinity") &&
        (($prefix_param_hash{'AdvPreferredLifetime'} eq "infinity") ||
         ($prefix_param_hash{'AdvPreferredLifetime'} > 
          $prefix_param_hash{'AdvValidLifetime'}))) {
        printf("Error: You have set AdvPreferredLifetime to ");
        printf("$prefix_param_hash{'AdvPreferredLifetime'}\n");
        printf("and AdvValidLifetime to ");
        printf("$prefix_param_hash{'AdvValidLifetime'}.\n");
        printf("AdvPreferredLifetime must be less than or equal to AdvValidLifetime.\n");
        exit(1);
    }

    # Write parameters out to config file
    print $FD_WR "    prefix $prefix {\n";
    foreach my $key (keys %prefix_param_hash) {
        print $FD_WR "        $key $prefix_param_hash{$key};\n";
    }

    print $FD_WR "    };\n";
}

# Parse params and write config file for one interface
sub do_interface {
    my $ifname = shift;
    my $intf = new Vyatta::Interface($ifname);
    die "Unknown interface type $ifname\n" unless $intf;
    my $param_root = $intf->path() . " ipv6 router-advert";
    
    # RFC-4861 parameters and their default values.
    # Parameters with fixed defined default values have those values
    # set here.  Those values may be simply over-ridden by user-selected
    # values.  Parameters that have algorithmic default values
    # have their value set to -1 here.  User-selected values can
    # over-ride them.  If the user doesn't select a value, a final
    # value is determined later on.
    my %param_hash = ( 'AdvSendAdvert' => 'off',
                       'MaxRtrAdvInterval' => 600,
                       'MinRtrAdvInterval' => -1,
                       'AdvManagedFlag' => 'off',
                       'AdvOtherConfigFlag' => 'off',
                       'AdvLinkMTU' => '0',
                       'AdvReachableTime' => '0',
                       'AdvRetransTimer' => '0',
                       'AdvCurHopLimit' => '64',
                       'AdvDefaultLifetime' => '-1',
                       'AdvDefaultPreference' => 'medium' );



    my @params = $config->listNodes($param_root);

    log_msg("params = @params\n");

    # Read in top-level params...
    foreach my $param (@params) {
        log_msg("Node: $param \n");

        my $value = $config->returnValue("$param_root $param");
        log_msg("Value: $value\n");

        if ($param eq "max-interval") {
            $param_hash{'MaxRtrAdvInterval'} = $value;
        } elsif ($param eq "min-interval") {
            $param_hash{'MinRtrAdvInterval'} = $value;
        } elsif ($param eq "managed-flag") {
            if ($value eq "true") {
                $param_hash{'AdvManagedFlag'} = 'on';
            } else {
                $param_hash{'AdvManagedFlag'} = 'off';
            }
        } elsif ($param eq "other-config-flag") {
            if ($value eq "true") {
                $param_hash{'AdvOtherConfigFlag'} = 'on';
            } else {
                $param_hash{'AdvOtherConfigFlag'} = 'off';
            }
        } elsif ($param eq "send-advert") {
            if ($value eq "true") {
                $param_hash{'AdvSendAdvert'} = 'on';
            } else {
                $param_hash{'AdvSendAdvert'} = 'off';
            }
        } elsif ($param eq "link-mtu") {
            $param_hash{'AdvLinkMTU'} = $value;
        } elsif ($param eq "reachable-time") {
            $param_hash{'AdvReachableTime'} = $value;
        } elsif ($param eq "retrans-timer") {
            $param_hash{'AdvRetransTimer'} = $value;
        } elsif ($param eq "cur-hop-limit") {
            $param_hash{'AdvCurHopLimit'} = $value;
        } elsif ($param eq "default-lifetime") {
            $param_hash{'AdvDefaultLifetime'} = $value;
        } elsif ($param eq "default-preference") {
            $param_hash{'AdvDefaultPreference'} = $value;
        } elsif ($param eq "prefix") {
            # Skip for now.  We'll do these later.
        } elsif ($param eq "name-server") {
            # Skip for now. Hack will be inserted at the end
        }
    }

    # Fill in remainig defaults
    if ($param_hash{'MinRtrAdvInterval'} == -1) {
        if ($param_hash{'MaxRtrAdvInterval'} > 9) {
            $param_hash{'MinRtrAdvInterval'} = 
                $param_hash{'MaxRtrAdvInterval'} * 0.33;
            # Round to nearest integer
            $param_hash{'MinRtrAdvInterval'} = 
                sprintf("%.0f", $param_hash{'MinRtrAdvInterval'});
        } else {
            $param_hash{'MinRtrAdvInterval'} = 3;
        }
    }

    if ($param_hash{'AdvDefaultLifetime'} == -1) {
        $param_hash{'AdvDefaultLifetime'} =
            $param_hash{'MaxRtrAdvInterval'} * 3;
    }

    # Validate values
    my $mtu_param = $param_hash{'AdvLinkMTU'};
    if ($mtu_param > 0) {
        my $live_mtu = `ip link show $ifname | grep mtu | awk '{ print \$5 }'`;
        $live_mtu =~ s/\n//;
        if ($live_mtu != $mtu_param) {
            printf("Warning: link-mtu parameter given ($mtu_param) is different from the MTU\n");
            printf("currently being used on $ifname ($live_mtu).\n");
        }
    }

    if ($param_hash{'MaxRtrAdvInterval'} > 1800) {
        printf("Error: MaxRtrAdvInterval value is $param_hash{'MaxRtrAdvInterval'}. It must be 1800 or less.\n");
        exit 1;
    }

    if ($param_hash{'MaxRtrAdvInterval'} < 4) {
        printf("Error: MaxRtrAdvInterval valueis $param_hash{'MaxRtrAdvInterval'}. It must be 4 or more\n");
        exit 1;
    }

    if ($param_hash{'MinRtrAdvInterval'} < 3) {
        printf("Error: MinRtrAdvInterval value is $param_hash{'MinRtrAdvInterval'}. It must be 3 or more\n");
        exit 1;
    }
    
    if ($param_hash{'MinRtrAdvInterval'} >
        ($param_hash{'MaxRtrAdvInterval'} * 0.75)) {
        printf("Error: MinRtrAdvInterval is $param_hash{'MinRtrAdvInterval'} and MaxRtrAdvInterval is $param_hash{'MaxRtrAdvInterval'}.\n");
        printf("MinRtrAdvInterval must be no greater than 3/4 MaxRtrAdvInterval\n");
        exit 1;
    }

    if (($param_hash{'AdvDefaultLifetime'} != 0) &&
        ($param_hash{'AdvDefaultLifetime'} <
         $param_hash{'MaxRtrAdvInterval'})) {
        printf("Error: AdvDefaultLifetime is $param_hash{'AdvDefaultLifetime'}");
        printf(" and MaxRtrAdvInterval is $param_hash{'MaxRtrAdvInterval'}.\n");
        printf("AdvDefaultLifetime must equal to or greater than MaxRtrAdvInterval.\n");
        exit 1;
    }

    if ($param_hash{'AdvDefaultLifetime'} > 9000) {
        printf("Error: AdvDefaultLifetime vlaue is $param_hash{'AdvDefaultLifetime'}.  It must be 9000 or less.\n");
        exit 1;
    }

    # Spit out top-level params to config file
    my $date = localtime;
    my $user = getpwuid($<) || 'Unknown';

    print $FD_WR "interface $ifname {\n";
    print $FD_WR "#   This section was automatically generated by the Vyatta\n";
    print $FD_WR "#   configuration sub-system.  Do not edit it.\n";
    print $FD_WR "#\n";
    print $FD_WR "#   Generated by $user on $date\n";
    print $FD_WR "#\n";
    print $FD_WR "    IgnoreIfMissing on;\n";
    foreach my $key (keys %param_hash) {
        print $FD_WR "    $key $param_hash{$key};\n";
    }

    # Process prefix params, if any
    my @prefix_params = $config->listNodes("$param_root prefix");
    log_msg("prefix_params = @prefix_params\n");

    foreach my $prefix (@prefix_params) {
        log_msg("prefix = $prefix\n");
        do_prefix($param_root, $prefix);
    }

    # Process Name Servers
    my @nameservers = $config->returnValues("$param_root name-server");
    log_msg("nameservers = @nameservers\n");
    if (@nameservers) {
        print $FD_WR "    RDNSS ";
        foreach my $nameserver (@nameservers) {
            print $FD_WR "$nameserver ";
        }
        print $FD_WR "{\n    };\n";
    }

    # Finish off config file
    print $FD_WR "};\n";
}

sub generate_conf {
    my $ifname = shift;
    log_msg("ifname = $ifname\n");

    # Generate config file for this interface into temporary string buffer
    my $conf_buffer;

    open $FD_WR, '>', \$conf_buffer
        or die "can't open temporary buffer: $!";

    $config = new Vyatta::Config;

    # Generate config file section for interface into temp file
    do_interface($ifname);

    close $FD_WR;

    if ( -e $conf_file ) {
        # Delete old parameter section for interface from global config file
        delete_conf($ifname);
    }

    # Cat newly generated temp file into global config file
    log_msg("copying in tempfile...\n");

    open my $CFG, '>>', $conf_file
        or die "can't open $conf_file: $!";

    print {$CFG} $conf_buffer;

    close $CFG;
}


#
# Delete the configuration information for an interface from the config file.
#
sub delete_conf {
    my $ifname = $_[0];
    log_msg("delete_conf ifname = $ifname\n");

    my $sedcmd = "sed -i -e \'/^interface $ifname {/,/^}/d\' $conf_file";
    log_msg("sedcmd is $sedcmd\n");

    my $exit_code = system($sedcmd);
    log_msg("exit_code is $exit_code\n");
    if ($exit_code != 0) {
        printf("Unable to edit radvd system config file.  Exit code $exit_code\n");
        exit 1;
    }
}

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
