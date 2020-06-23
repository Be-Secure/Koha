#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use Koha::Acquisition::Orders;
use Koha::Cities;
use Koha::Holds;
use Koha::Biblios;

# Dummy app for testing the plugin
use Mojolicious::Lite;

app->log->level('error');

plugin 'Koha::REST::Plugin::Objects';
plugin 'Koha::REST::Plugin::Query';
plugin 'Koha::REST::Plugin::Pagination';

get '/cities' => sub {
    my $c = shift;
    $c->validation->output($c->req->params->to_hash);
    my $cities = $c->objects->search(Koha::Cities->new);
    $c->render( status => 200, json => $cities );
};

get '/orders' => sub {
    my $c = shift;
    $c->stash('koha.embed', ( { fund => {} } ) );
    $c->validation->output($c->req->params->to_hash);
    my $orders = $c->objects->search(Koha::Acquisition::Orders->new);
    $c->render( status => 200, json => $orders );
};

get '/patrons/:patron_id/holds' => sub {
    my $c = shift;
    my $params = $c->req->params->to_hash;
    $params->{patron_id} = $c->stash("patron_id");
    $c->validation->output($params);
    my $holds_set = Koha::Holds->new;
    my $holds     = $c->objects->search( $holds_set );
    $c->render( status => 200, json => {count => scalar(@$holds)} );
};

get '/biblios' => sub {
    my $c = shift;
    my $output = $c->req->params->to_hash;
    $output->{query} = $c->req->json if defined $c->req->json;
    my $headers = $c->req->headers->to_hash;
    $output->{'x-koha-query'} = $headers->{'x-koha-query'} if defined $headers->{'x-koha-query'};
    $c->validation->output($output);
    my $biblios_set = Koha::Biblios->new;
    $c->stash("koha.embed", {
        "suggestions" => {
            children => {
                "suggester" => {}
            }
        }
    });
    my $biblios = $c->objects->search($biblios_set);
    $c->render( status => 200, json => {count => scalar(@$biblios), biblios => $biblios} );
};


# The tests
use Test::More tests => 10;
use Test::Mojo;

use t::lib::TestBuilder;
use Koha::Database;

my $t = Test::Mojo->new;

my $schema  = Koha::Database->new()->schema();
my $builder = t::lib::TestBuilder->new;

subtest 'objects.search helper' => sub {

    plan tests => 38;

    $schema->storage->txn_begin;

    # Remove existing cities to have more control on the search results
    Koha::Cities->delete;

    # Create three sample cities that match the query. This makes sure we
    # always have a "next" link regardless of Mojolicious::Plugin::OpenAPI version.
    $builder->build_object({
        class => 'Koha::Cities',
        value => {
            city_name => 'Manuel'
        }
    });
    $builder->build_object({
        class => 'Koha::Cities',
        value => {
            city_name => 'Manuela'
        }
    });
    $builder->build_object({
        class => 'Koha::Cities',
        value => {
            city_name => 'Manuelab'
        }
    });

    $t->get_ok('/cities?name=manuel&_per_page=1&_page=1')
        ->status_is(200)
        ->header_like( 'Link' => qr/<http:\/\/.*[\?&]_page=2.*>; rel="next",/ )
        ->json_has('/0')
        ->json_hasnt('/1')
        ->json_is('/0/name' => 'Manuel');

    $builder->build_object({
        class => 'Koha::Cities',
        value => {
            city_name => 'Emanuel'
        }
    });

    # _match=starts_with
    $t->get_ok('/cities?name=manuel&_per_page=4&_page=1&_match=starts_with')
        ->status_is(200)
        ->json_has('/0')
        ->json_has('/1')
        ->json_has('/2')
        ->json_hasnt('/3')
        ->json_is('/0/name' => 'Manuel')
        ->json_is('/1/name' => 'Manuela')
        ->json_is('/2/name' => 'Manuelab');

    # _match=ends_with
    $t->get_ok('/cities?name=manuel&_per_page=4&_page=1&_match=ends_with')
        ->status_is(200)
        ->json_has('/0')
        ->json_has('/1')
        ->json_hasnt('/2')
        ->json_is('/0/name' => 'Manuel')
        ->json_is('/1/name' => 'Emanuel');

    # _match=exact
    $t->get_ok('/cities?name=manuel&_per_page=4&_page=1&_match=exact')
        ->status_is(200)
        ->json_has('/0')
        ->json_hasnt('/1')
        ->json_is('/0/name' => 'Manuel');

    # _match=contains
    $t->get_ok('/cities?name=manuel&_per_page=4&_page=1&_match=contains')
        ->status_is(200)
        ->json_has('/0')
        ->json_has('/1')
        ->json_has('/2')
        ->json_has('/3')
        ->json_hasnt('/4')
        ->json_is('/0/name' => 'Manuel')
        ->json_is('/1/name' => 'Manuela')
        ->json_is('/2/name' => 'Manuelab')
        ->json_is('/3/name' => 'Emanuel');

    $schema->storage->txn_rollback;
};

subtest 'objects.search helper, sorting on mapped column' => sub {

    plan tests => 14;

    $schema->storage->txn_begin;

    # Have complete control over the existing cities to ease testing
    Koha::Cities->delete;

    $builder->build_object({ class => 'Koha::Cities', value => { city_name => 'A', city_country => 'Argentina' } });
    $builder->build_object({ class => 'Koha::Cities', value => { city_name => 'B', city_country => 'Argentina' } });

    $t->get_ok('/cities?_order_by=%2Bname&_order_by=+country')
      ->status_is(200)
      ->json_has('/0')
      ->json_has('/1')
      ->json_hasnt('/2')
      ->json_is('/0/name' => 'A')
      ->json_is('/1/name' => 'B');

    $t->get_ok('/cities?_order_by=-name')
      ->status_is(200)
      ->json_has('/0')
      ->json_has('/1')
      ->json_hasnt('/2')
      ->json_is('/0/name' => 'B')
      ->json_is('/1/name' => 'A');

    $schema->storage->txn_rollback;
};

subtest 'objects.search helper, encoding' => sub {

    plan tests => 5;

    $schema->storage->txn_begin;

    Koha::Cities->delete;

    $builder->build_object({ class => 'Koha::Cities', value => { city_name => 'A', city_country => 'Argentina' } });
    $builder->build_object({ class => 'Koha::Cities', value => { city_name => 'B', city_country => '❤Argentina❤' } });

    $t->get_ok('/cities?q={"country": "❤Argentina❤"}')
      ->status_is(200)
      ->json_has('/0')
      ->json_hasnt('/1')
      ->json_is('/0/name' => 'B');

    $schema->storage->txn_rollback;
};

subtest 'objects.search helper, embed' => sub {

    plan tests => 2;

    $schema->storage->txn_begin;

    my $order = $builder->build_object({ class => 'Koha::Acquisition::Orders' });

    $t->get_ok('/orders?order_id=' . $order->ordernumber)
      ->json_is('/0',$order->to_api({ embed => ( { fund => {} } ) }));

    $schema->storage->txn_rollback;
};

subtest 'objects.search helper, with path parameters and _match' => sub {
    plan tests => 8;

    $schema->storage->txn_begin;

    Koha::Holds->search()->delete;

    my $patron = Koha::Patrons->find(10);
    $patron->delete if $patron;
    $patron = $builder->build_object( { class => "Koha::Patrons" } );
    $patron->borrowernumber(10)->store;
    $builder->build_object(
        {
            class => "Koha::Holds",
            value => { borrowernumber => $patron->borrowernumber }
        }
    );

    $t->get_ok('/patrons/1/holds?_match=exact')
      ->json_is('/count' => 0, 'there should be no holds for borrower 1 with _match=exact');

    $t->get_ok('/patrons/1/holds?_match=contains')
      ->json_is('/count' => 0, 'there should be no holds for borrower 1 with _match=contains');

    $t->get_ok('/patrons/10/holds?_match=exact')
      ->json_is('/count' => 1, 'there should be 1 hold for borrower 10 with _match=exact');

    $t->get_ok('/patrons/10/holds?_match=contains')
      ->json_is('/count' => 1, 'there should be 1 hold for borrower 10 with _match=contains');

    $schema->storage->txn_rollback;
};

subtest 'object.search helper with query parameter' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $patron1 = $builder->build_object( { class => "Koha::Patrons" } );
    my $patron2 = $builder->build_object( { class => "Koha::Patrons" } );
    my $biblio1 = $builder->build_sample_biblio;
    my $biblio2 = $builder->build_sample_biblio;
    my $biblio3 = $builder->build_sample_biblio;
    my $suggestion1 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron1->borrowernumber, biblionumber => $biblio1->biblionumber} } );
    my $suggestion2 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio2->biblionumber} } );
    my $suggestion3 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio3->biblionumber} } );

    $t->get_ok('/biblios' => json => {"suggestions.suggester.patron_id" => $patron1->borrowernumber })
      ->json_is('/count' => 1, 'there should be 1 biblio with suggestions of patron 1');

    $t->get_ok('/biblios' => json => {"suggestions.suggester.patron_id" => $patron2->borrowernumber })
      ->json_is('/count' => 2, 'there should be 2 biblios with suggestions of patron 2');

    $schema->storage->txn_rollback;
};

subtest 'object.search helper with q parameter' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $patron1 = $builder->build_object( { class => "Koha::Patrons" } );
    my $patron2 = $builder->build_object( { class => "Koha::Patrons" } );
    my $biblio1 = $builder->build_sample_biblio;
    my $biblio2 = $builder->build_sample_biblio;
    my $biblio3 = $builder->build_sample_biblio;
    my $suggestion1 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron1->borrowernumber, biblionumber => $biblio1->biblionumber} } );
    my $suggestion2 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio2->biblionumber} } );
    my $suggestion3 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio3->biblionumber} } );

    $t->get_ok('/biblios?q={"suggestions.suggester.patron_id": "'.$patron1->borrowernumber.'"}')
      ->json_is('/count' => 1, 'there should be 1 biblio with suggestions of patron 1');

    $t->get_ok('/biblios?q={"suggestions.suggester.patron_id": "'.$patron2->borrowernumber.'"}')
      ->json_is('/count' => 2, 'there should be 2 biblios with suggestions of patron 2');

    $schema->storage->txn_rollback;
};

subtest 'object.search helper with x-koha-query header' => sub {
    plan tests => 4;

    $schema->storage->txn_begin;

    my $patron1 = $builder->build_object( { class => "Koha::Patrons" } );
    my $patron2 = $builder->build_object( { class => "Koha::Patrons" } );
    my $biblio1 = $builder->build_sample_biblio;
    my $biblio2 = $builder->build_sample_biblio;
    my $biblio3 = $builder->build_sample_biblio;
    my $suggestion1 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron1->borrowernumber, biblionumber => $biblio1->biblionumber} } );
    my $suggestion2 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio2->biblionumber} } );
    my $suggestion3 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio3->biblionumber} } );

    $t->get_ok('/biblios' => {'x-koha-query' => '{"suggestions.suggester.patron_id": "'.$patron1->borrowernumber.'"}'})
      ->json_is('/count' => 1, 'there should be 1 biblio with suggestions of patron 1');

    $t->get_ok('/biblios' => {'x-koha-query' => '{"suggestions.suggester.patron_id": "'.$patron2->borrowernumber.'"}'})
      ->json_is('/count' => 2, 'there should be 2 biblios with suggestions of patron 2');

    $schema->storage->txn_rollback;
};

subtest 'object.search helper with all query methods' => sub {
    plan tests => 6;

    $schema->storage->txn_begin;

    my $patron1 = $builder->build_object( { class => "Koha::Patrons" , value => {firstname=>'patron1'} } );
    my $patron2 = $builder->build_object( { class => "Koha::Patrons" , value => {firstname=>'patron2'} } );
    my $biblio1 = $builder->build_sample_biblio;
    my $biblio2 = $builder->build_sample_biblio;
    my $biblio3 = $builder->build_sample_biblio;
    my $suggestion1 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron1->borrowernumber, biblionumber => $biblio1->biblionumber} } );
    my $suggestion2 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio2->biblionumber} } );
    my $suggestion3 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio3->biblionumber} } );

    $t->get_ok('/biblios?q={"suggestions.suggester.firstname": "'.$patron1->firstname.'"}' => {'x-koha-query' => '{"suggestions.suggester.patron_id": "'.$patron1->borrowernumber.'"}'} => json => {"suggestions.suggester.cardnumber" => $patron1->cardnumber})
      ->json_is('/count' => 1, 'there should be 1 biblio with suggestions of patron 1');

    $t->get_ok('/biblios?q={"suggestions.suggester.firstname": "'.$patron2->firstname.'"}' => {'x-koha-query' => '{"suggestions.suggester.patron_id": "'.$patron2->borrowernumber.'"}'} => json => {"suggestions.suggester.cardnumber" => $patron2->cardnumber})
      ->json_is('/count' => 2, 'there should be 2 biblios with suggestions of patron 2');

    $t->get_ok('/biblios?q={"suggestions.suggester.firstname": "'.$patron1->firstname.'"}' => {'x-koha-query' => '{"suggestions.suggester.patron_id": "'.$patron2->borrowernumber.'"}'} => json => {"suggestions.suggester.cardnumber" => $patron2->cardnumber})
      ->json_is('/count' => 0, 'there shouldn\'t be biblios where suggester has patron1 fistname and patron2 id');

    $schema->storage->txn_rollback;
};

subtest 'object.search helper order by embedded columns' => sub {
    plan tests => 3;

    my $patron1 = $builder->build_object( { class => "Koha::Patrons" , value => {firstname=>'patron1'} } );
    my $patron2 = $builder->build_object( { class => "Koha::Patrons" , value => {firstname=>'patron2'} } );
    my $biblio1 = $builder->build_sample_biblio;
    my $biblio2 = $builder->build_sample_biblio;
    my $suggestion1 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron1->borrowernumber, biblionumber => $biblio1->biblionumber} } );
    my $suggestion2 = $builder->build_object( { class => "Koha::Suggestions", value => { suggestedby => $patron2->borrowernumber, biblionumber => $biblio2->biblionumber} } );

    $t->get_ok('/biblios?_order_by=-suggestions.suggester.firstname' => json => [{"me.biblio_id" => $biblio1->biblionumber}, {"me.biblio_id" => $biblio2->biblionumber}])
      ->json_is('/biblios/0/biblio_id' => $biblio2->biblionumber, 'Biblio 2 should be first')
      ->json_is('/biblios/1/biblio_id' => $biblio1->biblionumber, 'Biblio 1 should be second');

    $schema->storage->txn_begin;
}
