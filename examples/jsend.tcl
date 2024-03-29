#!/usr/bin/env tclsh

# jsend.tcl --
#
#       This file is an example provided with the XMPP library. It allows to
#       send messages via XMPP non-interactively. It was initially developed
#       by Marshall T. Rose and adapted to the XMPP library by Sergei Golovan.
#
# Copyright (c) 2008-2013 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require sha1
package require tls

package require xmpp
package require xmpp::transport::bosh
package require xmpp::auth
package require xmpp::sasl
package require xmpp::starttls
package require xmpp::roster
package require xmpp::delay

# Register IQ XMLNS
::xmpp::iq::register get * http://jabber.org/protocol/disco#info \
                           jsend::iqDiscoInfo
::xmpp::iq::register get * http://jabber.org/protocol/disco#items \
                           jsend::iqDiscoItems
::xmpp::iq::register get * jabber:iq:last    jsend::iqLast
::xmpp::iq::register get * jabber:iq:time    jsend::iqTime
::xmpp::iq::register get * jabber:iq:version jsend::iqVersion

namespace eval jsend {}

proc jsend::sendit {stayP to args} {
    global xlib
    global env

    variable lib
    variable sendit_result

    array set options [list -to          $to   \
                            -from        ""    \
                            -password    ""    \
                            -host        ""    \
                            -port        ""    \
                            -activity    ""    \
                            -type        chat  \
                            -subject     ""    \
                            -body        ""    \
                            -xhtml       ""    \
                            -date        ""    \
                            -description ""    \
                            -url         ""    \
                            -bosh        ""    \
                            -tls         false \
                            -starttls    true  \
                            -sasl        true  \
                            -digest      true]
    array set options $args

    if {[string equal $options(-host) ""]} {
        if {[string first @ $options(-from)] < 0} {
            set options(-host) [info hostname]
        } else {
            set options(-host) [::xmpp::jid::server $options(-from)]
        }
    }

    set params [list from]
    if {![string equal $options(-to) "-"]} {
        lappend params to
    }
    foreach k $params {
        if {[string first @ $options(-$k)] < 0} {
            if {[set x [string first / $options(-$k)]] >= 0} {
                set options(-$k) [string replace $options(-$k) $x $x \
                                         @$options(-host)/]
            } else {
                append options(-$k) @$options(-host)
            }
        }
        if {([string first @ $options(-$k)] == 0) \
                && ([info exists env(USER)])} {
            set options(-$k) $env(USER)$options(-$k)
        }
    }
    if {![string equal $options(-to) "-"]} {
        set options(-to) [list $options(-to)]
    }

    foreach k [list tls starttls] {
        switch -- [string tolower $options(-$k)] {
            1 - 0               {}
            false - no  - off   { set options(-$k) 0 }
            true  - yes - on    { set options(-$k) 1 }
            default {
                error "invalid value for -$k: $options(-$k)"
            }
        }
    }

    ::xmpp::jid::split $options(-from) node domain resource
    if {[string equal $resource ""]} {
        set resource "jsend"
    }

    if {[string equal $options(-body) ""] && $stayP < 2} {
        set options(-body) [read -nonewline stdin]
    }

    set options(-xlist) {}
    if {![string equal $options(-url)$options(-description) ""]} {
        lappend options(-xlist) \
                [::xmpp::xml::create x \
                       -xmlns jabber:x:oob \
                       -subelement [::xmpp::xml::create url \
                                        -cdata $options(-url)] \
                       -subelement [::xmpp::xml::create desc \
                                        -cdata $options(-description)]]
    }
    if {[string compare $options(-date) ""]} {
        lappend options(-xlist) \
                [::xmpp::delay::create $options(-date)]
    }
    if {![string equal $options(-xhtml) ""] \
            && ![string equal $options(-body) ""] \
            && $stayP < 1} {
        lappend options(-xlist) \
                [::xmpp::xml::create html \
                       -xmlns http://jabber.org/protocol/xhtml-im \
                       -subelement [::xmpp::xml::create body \
                                        -xmlns http://www.w3.org/1999/xhtml \
                                        -subelements [jsend::parse_xhtml \
                                                            $options(-xhtml)]]]
    }
    if {[string equal $options(-type) announce]} {
        set options(-type) normal
        set announce [sha1::sha1 \
                          [clock seconds]$options(-subject)$options(-body)]
        lappend options(-xlist) \
                [::xmpp::xml::create x \
                     -xmlns http://2entwine.com/protocol/gush-announce-1_0 \
                     -subelement [::xmpp::xml::create id -cdata $announce]]
    }

    set lib(lastwhat) $options(-activity)
    if {[catch { clock scan $options(-time) } lib(lastwhen)]} {
        set lib(lastwhen) [clock seconds]
    }

    set params {}
    foreach k [list body subject type xlist] {
        if {![string equal $options(-$k) ""]} {
            lappend params -$k $options(-$k)
        }
    }

    if {![info exists xlib]} {
        # Create an XMPP library instance
        set xlib [::xmpp::new]

        if (![string equal $options(-bosh) ""]) {
            set transport bosh
            set port 0
        } elseif {$options(-tls)} {
            set transport tls
            if {![string equal $options(-port) ""]} {
                set port $options(-port)
            } else {
                set port 5223
            }
        } else {
            set transport tcp
            if {![string equal $options(-port) ""]} {
                set port $options(-port)
            } else {
                set port 5222
            }
        }

        # Connect to a server
        ::xmpp::connect $xlib $options(-host) $port \
                              -transport $transport \
                              -url $options(-bosh)

        if {[string equal $options(-bosh) ""] && !$options(-tls) && $options(-starttls)} {
            # Open XMPP stream
            set sessionID [::xmpp::openStream $xlib $domain \
                                                    -version 1.0]

            ::xmpp::starttls::starttls $xlib

            ::xmpp::sasl::auth $xlib -username  $node \
                                     -password  $options(-password) \
                                     -resource  $resource \
                                     -digest    $options(-digest)
        } elseif {$options(-sasl)} {
            # Open XMPP stream
            set sessionID [::xmpp::openStream $xlib $domain \
                                                    -version 1.0]

            ::xmpp::sasl::auth $xlib -username  $node \
                                     -password  $options(-password) \
                                     -resource  $resource \
                                     -digest    $options(-digest)
        } else {
            # Open XMPP stream
            set sessionID [::xmpp::openStream $xlib $domain]

            # Authenticate
            ::xmpp::auth::auth $xlib -sessionid $sessionID \
                                     -username  $node \
                                     -password  $options(-password) \
                                     -resource  $resource
        }

        set roster [::xmpp::roster::new $xlib]
        ::xmpp::roster::get $roster
    }

    if {[string equal $options(-to) "-"]} {
        set options(-to) [::xmpp::roster::items $roster]
    }

    if {$stayP > 1} {
        ::xmpp::sendPresence $xlib -status Online

        if {[string equal $options(-type) groupchat]} {
            set nick [::xmpp::jid::jid $username $domain $resource]
            set nick [string range [sha1::sha1 $nick+[clock seconds]] 0 7]
            foreach to $options(-to) {
                ::xmpp::sendPresence $xlib -to $to/$nick
            }
        }
        return 1
    }

    foreach to $options(-to) {
        switch -- [eval [list ::xmpp::sendMessage $xlib $to] $params] {
            -1 -
            -2 {
                if {$stayP} {
                    set cmd [list ::LOG]
                } else {
                    set cmd [list error]
                }
                eval $cmd [list "error writing to socket, continuing..."]
                return 0
            }

            default {}
        }
    }
    if {!$stayP} {
        set jsend::stayP 0
        ::xmpp::disconnect $xlib -wait 1
    }

    return 1
}

proc jsend::iqDiscoInfo {xlib from xmlElement args} {
    ::LOG "jsend::iqDiscoInfo $from"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    if {[::xmpp::xml::isAttr $attrs node]} {
        return [list error cancel service-unavailable]
    }

    set identity [::xmpp::xml::create identity \
                                      -attrs [list name     jsend \
                                                   category client \
                                                   type     bot]]

    set subelements {}
    foreach var [list http://jabber.org/protocol/disco#info \
                      http://jabber.org/protocol/disco#items \
                      jabber:iq:last \
                      jabber:iq:time \
                      jabber:iq:version] {
        lappend subelements [::xmpp::xml::create feature \
                                    -attrs [list var $var]]
    }
    set xmldata \
        [::xmpp::xml::create query -xmlns       $xmlns \
                                   -attrs       [list type client] \
                                   -subelement  $identity \
                                   -subelements $subelements]
    return [list result $xmldata]
}

proc jsend::iqDiscoItems {xlib from xmlElement args} {
    ::LOG "jsend::iqDiscoItems $from"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    if {[::xmpp::xml::isAttr $attrs node]} {
        return [list error cancel service-unavailable]
    }

    return [list result [::xmpp::xml::create query -xmlns $xmlns]]
}

proc jsend::iqLast {xlib from xmlElement args} {
    variable lib

    ::LOG "jsend::iqLast $from"

    set now [clock seconds]
    set xmldata \
        [::xmpp::xml::create query -xmlns jabber:iq:last \
                                   -attrs [list seconds \
                                                [expr {$now - $lib(lastwhen)}]]]
    return [list result $xmldata]
}

proc jsend::iqTime {xlib from xmlElement args} {
    ::LOG "jsend::iqTime $from"

    set now [clock seconds]
    set gmtP true
    foreach {k f} [list utc     "%Y%m%dT%T" \
                        tz      "%Z"        \
                        display "%a %b %d %H:%M:%S %Z %Y"] {
        lappend tags [::xmpp::xml::create $k -cdata [clock format $now \
                                                           -format $f  \
                                                           -gmt    $gmtP]]
        set gmtP false
    }
    set xmldata [::xmpp::xml::create query -xmlns jabber:iq:time \
                                           -subelements $tags]
    return [list result $xmldata]
}

proc jsend::iqVersion {xlib from xmlElement args} {
    global argv0 tcl_platform

    ::LOG "jsend::iqVersion $from"

    foreach {k v} [list name    [file tail [file rootname $argv0]] \
                        version "1.0 (Tcl [info patchlevel])"      \
                        os      "$tcl_platform(os) $tcl_platform(osVersion)"] {
        lappend tags [::xmpp::xml::create $k -cdata $v]
    }
    set xmldata [::xmpp::xml::create query -xmlns jabber:iq:version \
                                           -subelements $tags]
    return [list result $xmldata]
}

proc client:reconnect {xlib} {
    jsend::reconnect
}

proc client:disconnect {xlib} {
    jsend::reconnect
}

proc client:status {args} {
    ::LOG "client:status $args"
}


namespace eval jsend {
    variable stayP 1
}

proc jsend::follow {file argv} {
    proc [namespace current]::reconnect {} \
         [list [namespace current]::reconnect_aux $argv]

    if {[catch { eval [list jsend::sendit 2] $argv } result]} {
        ::bgerror $result
        return
    }

    set buffer ""
    set fd ""
    set newP 1
    array set st [list dev 0 ino 0 size 0]

    for {set i 0} {1} {incr i} {
        if {[expr {$i % 5}] == 0} {
            if {[catch { file stat $file st2 } result]} {
                ::LOG $result
                break
            }

            if {($st(dev) != $st2(dev)) \
                    || ($st(ino) != $st2(ino)) \
                    || ($st(size) > $st2(size))} {
                if {$newP} {
                    catch { close $fd }
                }

                fconfigure [set fd [open $file { RDONLY }]] -blocking off
                unset st
                array set st [array get st2]

                if {!$newP && [string equal $st(type) file]} {
                    seek $fd 0 end
                }

                if {!$newP} {
                    set newP 0
                }

                if {[string length $buffer] > 0} {
                    if {[catch { eval [list jsend::sendit 1] $argv \
                                      [parse $buffer] \
                                      [list -body $buffer] } result]} {
                        ::LOG $result
                        break
                    } elseif {$result} {
                        set buffer ""
                    }
                }
            }
        }

        if {[fblocked $fd]} {
        } elseif {[catch {
            set len [string length [set line [read $fd]]]
            append buffer $line
        } result]} {
            ::LOG $result
            break
        } elseif {[set x [string first "\n" $buffer]] < 0} {
        } else {
            set body [string range $buffer 0 [expr {$x-1}]]
            while {[catch { eval [list jsend::sendit 1] $argv [parse $body] \
                                 [list -body $body] } result]} {
                ::LOG $result
            }
            if {$result} {
                set buffer [string range $buffer [expr {$x + 1}] end]
            }
        }

        after 1000 "set alarmP 1"
        vwait alarmP
    }
}

proc jsend::parse {line} {
    set args {}

    if {![string equal [string index $line 15] " "]} {
        return $args
    }
    catch { lappend args -time [clock scan [string range $line 0 14]] }

    set line [string range $line 16 end]
    if {([set d [string first " " $line]] > 0) \
            && ([string first ": " $line] > $d)} {
        lappend args -activity [string trim [string range $line $d end]]
    }

    return $args
}

proc jsend::reconnect_aux {argv} {
    variable stayP

    while {$stayP} {
        after [expr {60*1000}]
        if {![catch { eval [list jsend::sendit 2] $argv } result]} {
            break
        }

        ::LOG $result
    }
}

proc jsend::parse_xhtml {text} {
    return [::xmpp::xml::parseData "<body>$text</body>"]
}

proc ::LOG {text} {
#    puts stderr $text
}

proc ::debugmsg {args} {
#    ::LOG "debugmsg: $args"
}

proc ::bgerror {err} {
    global errorInfo

    ::LOG "$err\n$errorInfo"
}


set status 1

array set jsend::lib [list lastwhen [clock seconds] lastwhat ""]

if {[string equal [file tail [lindex $argv 0]] "jsend.tcl"]} {
    incr argc -1
    set argv [lrange $argv 1 end]
}

if {(([set x [lsearch -exact $argv -help]] >= 0) \
            || ([set x [lsearch -exact $argv --help]] >= 0)) \
        && (($x == 0) || ([expr {$x % 2}]))} {
    puts stdout \
"usage: jsend.tcl recipient ?options...?
            -follow      file
            -pidfile     file
            -from        jid
            -host        hostname
            -port        number
            -password    string
            -type        string (e.g., 'chat')
            -subject     string
            -body        string
            -xhtml       string
            -description string
            -url         string
            -bosh        string (BOSH URL)
            -tls         boolean (e.g., 'false')
            -starttls    boolean (e.g., 'true')
            -sasl        boolean (e.g., 'true')

If recipient is '-', roster is used.

If both '-body' and '-follow' are absent, the standard input is used.

The file .jsendrc.tcl in the current or in home directory is consulted,
e.g.,

    set args {-from fred@example.com/bedrock -password wilma}

for default values."

    set status 0
} elseif {($argc < 1) || (![expr {$argc % 2}])} {
    puts stderr "usage: jsend.tcl recipent ?-key value?..."
} elseif {[catch {
    if {([file exists [set file .jsendrc.tcl]]) \
            || ([file exists [set file ~/.jsendrc.tcl]])} {
        set args {}

        source $file

        array set at [list -permissions 600]
        array set at [file attributes $file]

        if {[set x [lsearch -exact $args "-password"]] >= 0 \
                    && ![expr {$x % 2}] \
                    && ![string match *00 $at(-permissions)]} {
            error "file should be mode 0600"
        }

        if {[llength $args] > 0} {
            set argv [eval [list linsert $argv 1] $args]
        }
    }
} result]} {
    puts stderr "error in $file: $result"
} elseif {[set x [lsearch -exact $argv "-follow"]] > 0 && [expr {$x % 2}]} {
    set keep_alive 1
    set keep_alive_interval 3

    if {[set y [lsearch -exact $argv "-pidfile"]] > 0 && [expr {$y % 2}]} {
        set fd [open [set pf [lindex $argv [expr {$y + 1}]]] \
                     {WRONLY CREAT TRUNC}]
        puts $fd [pid]
        close $fd
    }

    jsend::follow [lindex $argv [expr {$x + 1}]] $argv

    catch { file delete -- $pf }
} elseif {[catch { eval [list jsend::sendit 0] $argv } result]} {
    puts stderr $result
} else {
    set status 0
}

exit $status

# vim:ft=tcl:ts=8:sw=4:sts=4:et
