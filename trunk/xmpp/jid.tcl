# jid.tcl --
#
#       This file is part of the XMPP library. It implements the routines to
#       work with JIDs
#
# Copyright (c) 2008-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::jid 0.1

namespace eval ::xmpp::jid {
    namespace export jid split node server resource stripResource \
                     normalize equal

    if {![catch {package require stringprep 1.0.1}]} {
        variable Stringprep 1

        ::stringprep::register Nameprep \
                -mapping {B.1 B.2} \
                -normalization KC \
                -prohibited {A.1 C.1.2 C.2.2 C.3 C.4 C.5 C.6 C.7 C.8 C.9} \
                -prohibitedBidi 1

        ::stringprep::register Nodeprep \
                -mapping {B.1 B.2} \
                -normalization KC \
                -prohibited {A.1 C.1.1 C.1.2 C.2.1 C.2.2 C.3 C.4 C.5 C.6
                             C.7 C.8 C.9} \
                -prohibitedList {0x22 0x26 0x27 0x2f 0x3a 0x3c 0x3e 0x40} \
                -prohibitedBidi 1

        ::stringprep::register Resourceprep \
                -mapping {B.1} \
                -normalization KC \
                -prohibited {A.1 C.1.2 C.2.1 C.2.2 C.3 C.4 C.5 C.6 C.7
                             C.8 C.9} \
                -prohibitedBidi 1
    } else {
        variable Stringprep 0
    }
}

# ::xmpp::jid::jid --
#
#       Create JID from node, server and resource parts.
#
# Arguments:
#       node        JID node.
#       server      JID server.
#       resource    (optional, defaults to "") JID resource.
#
# Result:
#       A constructed JID (arguments joined by @ and /).
#
# Side effects:
#       None.

proc ::xmpp::jid::jid {node server {resource ""}} {
    set jid $server
    if {![string equal $node ""]} {
        set jid $node@$jid
    }
    if {![string equal $resource ""]} {
        set jid $jid/$resource
    }
    return $jid
}

# ::xmpp::jid::split --
#
#       Splits the given JID into 3 variables.
#
# Arguments:
#       jid             JID.
#       nodeVar         Variable for JID node.
#       serverVar       Variable for JID server.
#       resourceVar     Variable for JID resource.
#
# Result:
#       An empty string.
#
# Side effects:
#       Three variables are assigned.

proc ::xmpp::jid::split {jid nodeVar serverVar resourceVar} {
    upvar 1 $nodeVar node $serverVar server $resourceVar resource

    set node     [node $jid]
    set server   [server $jid]
    set resource [resource $jid]

    return
}

# ::xmpp::jid::node --
#
#       Extract node part from JID.
#
# Arguments:
#       jid         JID.
#
# Result:
#       An extracted node (part of JID before the first @ if it doesn't belong
#       to a resource, or empty string).
#
# Side effects:
#       None.

proc ::xmpp::jid::node {jid} {
    set a [string first @ $jid]
    if {$a < 0} {
        return
    } else {
        set b [string first / $jid]
        if {$b >= 0 && $a > $b} {
            return
        } else {
            string range $jid 0 [incr a -1]
        }
    }
}

# ::xmpp::jid::server --
#
#       Extract server part from JID.
#
# Arguments:
#       jid         JID.
#
# Result:
#       An extracted server (part of JID between the first @ and the first /).
#
# Side effects:
#       None.

proc ::xmpp::jid::server {jid} {
    set a [string first @ $jid]
    set b [string first / $jid]

    if {$a < 0} {
        if {$b < 0} {
            return $jid
        } else {
            string range $jid 0 [incr b -1]
        }
    } else {
        if {$b < 0} {
            string range $jid [incr a] end
        } elseif {$a >= $b} {
            string range $jid 0 [incr b -1]
        } else {
            string range $jid [incr a] [incr b -1]
        }
    }
}

# ::xmpp::jid::resource --
#
#       Extract resource part from JID.
#
# Arguments:
#       jid         JID.
#
# Result:
#       An extracted resource (part of JID after the first /).
#
# Side effects:
#       None.

proc ::xmpp::jid::resource {jid} {
    set b [string first / $jid]
    if {$b < 0} {
        return
    } else {
        string range $jid [incr b] end
    }
}

# ::xmpp::jid::bareJid --
#
#       Remove resource part from JID.
#
# Arguments:
#       jid         JID.
#
# Result:
#       A JID constructed from node and server parts extracted from the
#       given JID.
#
# Side effects:
#       None.

proc ::xmpp::jid::bareJid {jid} {
    jid [node $jid] [server $jid]
}

# ::xmpp::jid::stripResource --
#
#       The same as bareJid (for backward compatibility.
#
# Arguments:
#       jid         JID.
#
# Result:
#       A JID constructed from node and server parts extracted from the
#       given JID.
#
# Side effects:
#       None.

proc ::xmpp::jid::stripResource {jid} {
    bareJid $jid
}

# ::xmpp::jid::normalize --
#
#       Normalize JID for comparison. In case if stringprep package is loaded
#       it means applying the correspondent stringprep profiles to JID node,
#       server and resource. If stringprep isn'r available then JID node and
#       server parts are simply converted to lowercase.
#
# Arguments:
#       jid         JID.
#
# Result:
#       A normalised JID with either all its parts stringprepped or with node
#       and server parts converted to lowercase. If JID is malformed then the
#       error is returned.
#
# Side effects:
#       None.

proc ::xmpp::jid::normalize {jid} {
    variable Stringprep

    if {$Stringprep} {
        set node     [::stringprep::stringprep Nodeprep [node $jid]]
        set server   [::stringprep::stringprep Nameprep [server $jid]]
        set resource [::stringprep::stringprep Resourceprep [resource $jid]]
    } else {
        set node     [string tolower [node $jid]]
        set server   [string tolower [server $jid]]
        set resource [resource $jid]
    }

    jid $node $server $resource
}

# ::xmpp::jid::equal --
#
#       Compare two normalized JIDs.
#
# Arguments:
#       jid1        JID to compare.
#       jid1        JID to compare.
#
# Result:
#       1 if normalized JIDs are equal, 0 otherwise. Error if some of the JIDs
#       is malformed.
#
# Side effects:
#       None.

proc ::xmpp::jid::equal {jid1 jid2} {
    string equal [normalize $jid1] [normalize $jid2]
}

# vim:ts=8:sw=4:sts=4:et
