#!/usr/bin/perl

#
# Copyright 2020 Prosentient Systems
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use strict;
use warnings;
use Test::More tests => 14;
use Test::Warn;

use t::lib::Mocks;
use_ok("Koha::Middleware::RealIP");

my ($remote_address,$x_forwarded_for_header,$address);

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "";
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'1.1.1.1',"There is no X-Forwarded-For header, so just use the remote address");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2";
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'1.1.1.1',"Don't trust 1.1.1.1 as a proxy, so use it as the remote address");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2";
t::lib::Mocks::mock_config('koha_trusted_proxies', '1.1.1.1');
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'2.2.2.2',"Trust proxy (1.1.1.1), so use the X-Forwarded-For header for the remote address");


$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2,3.3.3.3";
t::lib::Mocks::mock_config('koha_trusted_proxies', '1.1.1.1 3.3.3.3');
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'2.2.2.2',"Trust multiple proxies (1.1.1.1 and 3.3.3.3), so use the X-Forwaded-For <client> portion for the remote address");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2,3.3.3.3";
t::lib::Mocks::mock_config('koha_trusted_proxies', 'bad configuration');
warnings_are {
    $address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
} ["could not parse bad","could not parse configuration"],"Warn on misconfigured koha_trusted_proxies";
is($address,'1.1.1.1',"koha_trusted_proxies is misconfigured so ignore the X-Forwarded-For header");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2";
t::lib::Mocks::mock_config('koha_trusted_proxies', 'bad 1.1.1.1');
warning_is {
    $address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
} "could not parse bad","Warn on partially misconfigured koha_trusted_proxies";
is($address,'2.2.2.2',"koha_trusted_proxies contains an invalid value but still includes one correct value, which is relevant, so use X-Forwarded-For header");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2";
t::lib::Mocks::mock_config('koha_trusted_proxies', '1.1.1.0/24');
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'2.2.2.2',"Trust proxy (1.1.1.1) using CIDR notation, so use the X-Forwarded-For header for the remote address");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2";
t::lib::Mocks::mock_config('koha_trusted_proxies', '1.1.1');
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'2.2.2.2',"Trust proxy (1.1.1.1) using abbreviated notation, so use the X-Forwarded-For header for the remote address");

$remote_address = "1.1.1.1";
$x_forwarded_for_header = "2.2.2.2";
t::lib::Mocks::mock_config('koha_trusted_proxies', '1.1.1.0:255.255.255.0');
$address = Koha::Middleware::RealIP::get_real_ip( $remote_address, $x_forwarded_for_header );
is($address,'2.2.2.2',"Trust proxy (1.1.1.1) using an IP address and netmask separated by a colon, so use the X-Forwarded-For header for the remote address");

require Net::Netmask;
SKIP: {
    skip "Net::Netmask at 1.9104+ supports IPv6", 2 unless Net::Netmask->VERSION < 1.9104;

    $remote_address         = "2001:db8:1234:5678:abcd:1234:abcd:1234";
    $x_forwarded_for_header = "2.2.2.2";
    t::lib::Mocks::mock_config( 'koha_trusted_proxies', '2001:db8:1234:5678::/64' );
    warning_is {
        $address = Koha::Middleware::RealIP::get_real_ip( $remote_address,
            $x_forwarded_for_header );
    }
    "could not parse 2001:db8:1234:5678::/64",
      "Warn on IPv6 koha_trusted_proxies";
    is(
        $address,
        '2001:db8:1234:5678:abcd:1234:abcd:1234',
        "IPv6 support was added in 1.9104 version of Net::Netmask"
    );
}
