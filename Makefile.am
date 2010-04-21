cfgdir		 = $(datadir)/vyatta-cfg/templates
opdir		 = $(datadir)/vyatta-op/templates
share_perl5dir	 = $(datarootdir)/perl5
libudevdir	 = /lib/udev
etcudevdir	 = /etc/udev
initddir	 = /etc/init.d
gentmpdir	 = generated-templates
modprobedir	 = /etc/modprobe.d

sysconf_DATA	 =
sbin_SCRIPTS	 =

sbin_SCRIPTS += scripts/vyatta_gen_radvd.pl
sbin_SCRIPTS += scripts/vyatta-ipv6-eui64.pl
sbin_SCRIPTS += scripts/vyatta-dhcpv6-client.pl

modprobe_SCRIPTS = etc/modprobe.d/vyatta_ipv6_noautoconf

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

all-local:
	rm -rf $(gentmpdir)
	./gen-interface-templates.pl $(gentmpdir)

clean-local:
	rm -rf $(gentmpdir)

install-exec-hook:
	cd $(gentmpdir); $(cpiop) $(DESTDIR)$(cfgdir) ; cd ..
	cd templates-op; $(cpiop) $(DESTDIR)$(opdir) ; cd ..




