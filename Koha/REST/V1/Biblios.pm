package Koha::REST::V1::Biblios;

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

use Mojo::Base 'Mojolicious::Controller';

use Koha::Biblios;
use Koha::RecordProcessor;
use C4::Biblio qw(DelBiblio);

use MARC::Record::MiJ;

use Try::Tiny;

=head1 API

=head2 Methods

=head3 get

Controller function that handles retrieving a single biblio object

=cut

sub get {
    my $c = shift->openapi->valid_input or return;

    my $attributes;
    $attributes = { prefetch => [ 'metadata' ] } # don't prefetch metadata if not needed
        unless $c->req->headers->accept =~ m/application\/json/;

    my $biblio = Koha::Biblios->find( { biblionumber => $c->validation->param('biblio_id') }, $attributes );

    unless ( $biblio ) {
        return $c->render(
            status  => 404,
            openapi => {
                error => "Object not found."
            }
        );
    }

    return try {

        if ( $c->req->headers->accept =~ m/application\/json/ ) {
            return $c->render(
                status => 200,
                json   => $biblio->to_api
            );
        }
        else {
            my $record = $biblio->metadata->record;

            $c->respond_to(
                marcxml => {
                    status => 200,
                    format => 'marcxml',
                    text   => $record->as_xml_record
                },
                mij => {
                    status => 200,
                    format => 'mij',
                    data   => $record->to_mij
                },
                marc => {
                    status => 200,
                    format => 'marc',
                    text   => $record->as_usmarc
                },
                txt => {
                    status => 200,
                    format => 'text/plain',
                    text   => $record->as_formatted
                },
                any => {
                    status  => 406,
                    openapi => [
                        "application/json",
                        "application/marcxml+xml",
                        "application/marc-in-json",
                        "application/marc",
                        "text/plain"
                    ]
                }
            );
        }
    }
    catch {
        $c->unhandled_exception($_);
    };
}

=head3 delete

Controller function that handles deleting a biblio object

=cut

sub delete {
    my $c = shift->openapi->valid_input or return;

    my $biblio = Koha::Biblios->find( $c->validation->param('biblio_id') );

    if ( not defined $biblio ) {
        return $c->render(
            status  => 404,
            openapi => { error => "Object not found" }
        );
    }

    return try {
        my $error = DelBiblio( $biblio->id );

        if ($error) {
            return $c->render(
                status  => 409,
                openapi => { error => $error }
            );
        }
        else {
            return $c->render( status => 204, openapi => "" );
        }
    }
    catch {
        $c->unhandled_exception($_);
    };
}

=head3 get_public

Controller function that handles retrieving a single biblio object

=cut

sub get_public {
    my $c = shift->openapi->valid_input or return;

    my $biblio = Koha::Biblios->find(
        { biblionumber => $c->validation->param('biblio_id') },
        { prefetch     => ['metadata'] } );

    unless ($biblio) {
        return $c->render(
            status  => 404,
            openapi => {
                error => "Object not found."
            }
        );
    }

    return try {

        my $record = $biblio->metadata->record;

        my $opachiddenitems_rules = C4::Context->yaml_preference('OpacHiddenItems');
        my $patron = $c->stash('koha.user');

        # Check if the biblio should be hidden for unprivileged access
        # unless there's a logged in user, and there's an exception for it's
        # category
        unless ( $patron and $patron->category->override_hidden_items ) {
            if ( $biblio->hidden_in_opac({ rules => $opachiddenitems_rules }) )
            {
                return $c->render(
                    status  => 404,
                    openapi => {
                        error => "Object not found."
                    }
                );
            }
        }

        my $marcflavour = C4::Context->preference("marcflavour");

        my $record_processor = Koha::RecordProcessor->new({
            filters => 'ViewPolicy',
            options => {
                interface => 'opac',
                frameworkcode => $biblio->frameworkcode
            }
        });
        # Apply framework's filtering to MARC::Record object
        $record_processor->process($record);

        $c->respond_to(
            marcxml => {
                status => 200,
                format => 'marcxml',
                text   => $record->as_xml_record
            },
            mij => {
                status => 200,
                format => 'mij',
                data   => $record->to_mij
            },
            marc => {
                status => 200,
                format => 'marc',
                text   => $record->as_usmarc
            },
            txt => {
                status => 200,
                format => 'text/plain',
                text   => $record->as_formatted
            },
            any => {
                status  => 406,
                openapi => [
                    "application/marcxml+xml",
                    "application/marc-in-json",
                    "application/marc",
                    "text/plain"
                ]
            }
        );
    }
    catch {
        return $c->render(
            status  => 500,
            openapi => { error => "Something went wrong, check the logs ($_)" }
        );
    };
}

1;
