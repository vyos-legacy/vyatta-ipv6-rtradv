cfgdir		 = $(datadir)/vyatta-cfg/templates
opdir		 = $(datadir)/vyatta-op/templates
share_perl5dir	 = $(datarootdir)/perl5
libudevdir	 = /lib/udev
etcudevdir	 = /etc/udev
initddir	 = /etc/init.d
gentmpdir	 = generated-templates
modprobedir	 = $(sysconfdir)/modprobe.d

sysconf_DATA	 =
sbin_SCRIPTS	 =

sbin_SCRIPTS += scripts/vyatta_gen_radvd.pl
sbin_SCRIPTS += scripts/vyatta-ipv6-eui64.pl

modprobe_DATA = etc/modprobe.d/ipv6.conf

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

all-local:
	rm -rf $(gentmpdir)
	./gen-interface-templates.pl $(gentmpdir)
# Only the radvd functions are compatible with pppoe interfaces; other functions are implemented in vyatta-cfg-op-pppoe
	rm -r $(gentmpdir)/interfaces/ethernet/node.tag/pppoe/node.tag/ipv6/{address,disable-forwarding,dup-addr-detect-transmits}

clean-local:
	rm -rf $(gentmpdir)

install-exec-hook:
	cd $(gentmpdir); $(cpiop) $(DESTDIR)$(cfgdir) ; cd ..
