SNORTSENTRY
===========

snortsentry is a Perl script that enhances system security by monitoring
Snort alert logs and automatically adding source addresses of suspicious
traffic to a pf(4) table or anchor. Hosts added to the table will have
their packets dropped by the packet filter.

PF SETUP
--------

OPTION 01: TABLES

Before running snortsentry, pf(4) must be configured with a table or
anchor that will receive the blocked addresses.

Example /etc/pf.conf configuration:

    table <snort_block> persist
    block in quick from <snort_block>

Reload pf(4) after editing the configuration:

    # pfctl -f /etc/pf.conf


OPTION 02: ANCHORS

snortsentry can also place blocked addresses into a dedicated pf(4) anchor
instead of a table. Anchors allow rules to be loaded into a separate,
named subsection of the main pf(4) ruleset. This can be useful when the
script needs to insert complete pf(4) rules rather than simply update a
table.

To use an anchor, define it in /etc/pf.conf:

    anchor "snortsentry"

Optionally load a ruleset for the anchor:

    load anchor "snortsentry" from "/etc/pf.snortsentry"

snortsentry will then populate this anchor with block rules such as:

    block in quick from x.x.x.x

After creating the anchor, reload pf(4):

    # pfctl -f /etc/pf.conf

Anchors offer flexibility for scripts that must manage their own pf(4)
ruleset, but for maintaining lists of dynamic IP addresses a pf(4) table
is typically simpler and more efficient.


CONFIGURATION
-------------

The main configuration file is:

    /etc/snort/snortsentry.conf

This file defines:

* Path to the Snort alert log to monitor.
* pf(4) table or anchor name (e.g. <snort_block>).
* Logging and verbosity options.


PRIVILEGES
----------

snortsentry requires root privileges to modify pf(4) tables.

If the script supports privilege dropping, an unprivileged user may be
set via rcctl(8):

    # rcctl set snortsentry user "_snortsentry"

If the program writes persistent data, ensure the files are owned by the
configured user:

    # chown -R _snortsentry /var/snortsentry


LOGGING
-------

snortsentry logs to:

    /var/log/snortsentry.log

Create the file if it does not already exist:

    # touch /var/log/snortsentry.log

Add a newsyslog(8) entry such as:

    /var/log/snortsentry.log    644  5  100  *  Z

Configure syslog(8) with:

    !!snortsentry
    *.*     /var/log/snortsentry.log
    !*

Then reload syslogd(8).


SERVICE MANAGEMENT
------------------

snortsentry is managed through rcctl(8) using its rc.d script.

Enable the service:

    # rcctl enable snortsentry

Start it immediately:

    # rcctl start snortsentry

Other useful commands:

    # rcctl check snortsentry
    # rcctl stop snortsentry
    # rcctl reload snortsentry    (if supported)


ALTERNATIVE STARTUP VIA rc.local
--------------------------------

If rcctl(8) is not used, the script may be started from /etc/rc.local:

    if [ -x /usr/local/sbin/snortsentry ]; then
        /usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf &
    fi


MANUAL USAGE
------------

snortsentry may be run manually:

    # /usr/local/sbin/snortsentry -f /etc/snort/snortsentry.conf


AUTHOR
------

David Peter, Tangent Networks
