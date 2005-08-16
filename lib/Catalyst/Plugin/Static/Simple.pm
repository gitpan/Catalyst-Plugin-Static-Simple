package Catalyst::Plugin::Static::Simple;

use strict;
use base qw/Class::Accessor::Fast Class::Data::Inheritable/;
use File::Slurp;
use File::stat;
use MIME::Types;
use NEXT;

our $VERSION = '0.02';

__PACKAGE__->mk_classdata('_mime_types');
__PACKAGE__->mk_accessors('_served_static');

=head1 NAME

Catalyst::Plugin::Static::Simple - Make serving static pages painless.

=head1 SYNOPSIS

    use Catalyst;
    MyApp->setup( qw/Static::Simple/ );
    
=head1 DESCRIPTION

The Static::Simple plugin is designed to make serving static content in your
application during development quick and easy, without requiring a single
line of code from you.

It will detect static files used in your application by looking for file
extensions in the URI.  By default, you can simply load this plugin and it
will immediately begin serving your static files with the correct MIME type.
The light-weight MIME::Types module is used to map file extensions to
IANA-registered MIME types.

Note that actions mapped to paths using periods (.) will still operate
properly.

You may further tweak the operation by adding configuration options, described
below.

=head1 CONFIGURATION

Configuration is completely optional and is specified within MyApp->config->{static}.

Define a list of top-level directories beneath your 'root' directory that
should always be served in static mode.  Regular expressions may be
specified using qr//.

    MyApp->config->{static}->{dirs} => [
        'static',
        qr/^(images|css)/,
    ]
    
To override or add to the default MIME types set by the MIME::Types module,
you may enter your own extension to MIME type mapping. 

    MyApp->config->{static}->{mime_types} => {
        jpg => 'images/jpg',
        png => 'image/png',
    }    
    
Enable additional debugging information printed in the Catalyst log.  This
is automatically enabled when running Catalyst in -Debug mode.

    MyApp->config->{static}->{debug} => 1

=cut

sub dispatch {
    my $c = shift;
    
    my $path = $c->req->path;
    
    # is the URI in a static-defined path?
    foreach my $dir ( @{ $c->config->{static}->{dirs} } ) {
        my $re = ( $dir =~ /^qr\// ) ? eval $dir : qr/^${dir}/;
        if ( $path =~ $re ) {
            $c->log->debug( "Static::Simple: Serving from defined directory" )
                if ( $c->config->{static}->{debug} );
            return $c->_serve_static;
        }
    }
    
    # is this a real file?
    if ( -f $c->config->{root} . '/' . $path ) {
        if ( my $type = $c->_ext_to_type ) {
            return $c->_serve_static( $type );
        }
    }
    
    return $c->NEXT::dispatch(@_);
}

sub finalize {
    my $c = shift;
    
    # return DECLINED when under mod_perl
    if ( $c->_served_static && $c->engine =~ /Apache::MP(\d{2})/ ) {
        my $engine = $1;
        $c->log->debug( "Static::Simple: returning DECLINED to Apache" )
            if ( $c->config->{static}->{debug} );
        no strict 'subs';
        if ( $engine == 13 ) {
            return Apache::Constants::DECLINED;
        } elsif ( $engine == 19 ) {
            return Apache::Const::DECLINED;
        } elsif ( $engine == 20 ) {
            return Apache2::Const::DECLINED;
        }
    }
    
    if ( $c->res->status =~ /^(1\d\d|[23]04)$/ ) {
        $c->res->headers->remove_content_headers;
        return $c->finalize_headers;
    }
    return $c->NEXT::finalize(@_);
}

sub setup {
    my $c = shift;
    
    $c->NEXT::setup(@_);
    
    $c->config->{static}->{dirs} ||= [];
    $c->config->{static}->{mime_types} ||= {};
    $c->config->{static}->{debug} ||= $c->debug;
    
    # load up a MIME::Types object, only loading types with
    # at least 1 file extension
    $c->_mime_types( MIME::Types->new( only_complete => 1 ) );
}

sub _ext_to_type {
    my $c = shift;
    
    my $path = $c->req->path;
    my $type;
    
    if ( $path =~ /.*\.(\S{1,})$/ ) {
        my $ext = $1;
        my $user_types = $c->config->{static}->{mime_types};
        if ( $type = $user_types->{$ext} || $c->_mime_types->mimeTypeOf( $ext ) ) {
            $c->log->debug( "Static::Simple: Serving known file extension '$ext' as $type" )
                if ( $c->config->{static}->{debug} );            
            return $type;
        } else {
            $type = 'text/plain';
            $c->log->debug( "Static::Simple: Unknown file extension '$ext', serving as text/plain" )
                if ( $c->config->{static}->{debug} );
        }
    }
    
    return undef;
}

sub _serve_static {
    my ( $c, $type ) = @_;
    
    # abort if running under mod_perl
    # note that we do not use the Apache method if the user has defined
    # custom MIME types, as Apache would not know about them
    if ( $c->engine =~ /Apache/ && 
         !keys %{ $c->config->{static}->{mime_types} } ) {
        $c->_served_static( 1 );
        return undef;
    }
    
    my $path = $c->req->path;
    
    unless ( -f $c->config->{root} . '/' . $path ) {
        $c->log->debug( "Static::Simple: File not found: $path" )
            if ( $c->config->{static}->{debug} );
        $c->res->status( 404 );
        return 0;
    }
    
    $type = $c->_ext_to_type unless ( $type );
    
    $path = $c->config->{root} . '/' . $path;    
    my $stat = stat( $path );

    # the below code all from C::P::Static
    if ( $c->req->headers->if_modified_since ) {
        if ( $c->req->headers->if_modified_since == $stat->mtime ) {
            $c->res->status( 304 ); # Not Modified
            $c->res->headers->remove_content_headers;
            return 1;
        }
    }

    my $content = read_file( $path );
    $c->res->headers->content_type( $type );
    $c->res->headers->content_length( $stat->size );
    $c->res->headers->last_modified( $stat->mtime );
    $c->res->output( $content );
    return 1;  
}
    
=head1 SEE ALSO

L<Catalyst>, L<Catalyst::Plugin::Static>, L<http://www.iana.org/assignments/media-types/>

=head1 AUTHOR

Andy Grundman, C<andy@hybridized.org>

=head1 THANKS

The authors of Catalyst::Plugin::Static:

Sebastian Riedel, C<sri@cpan.org>

Christian Hansen, C<ch@ngmedia.com>

Marcus Ramberg, C<mramberg@cpan.org>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
