# -*-perl-*-
# Creation date: 2003-08-13 20:23:50
# Authors: Don
# Change log:
# $Id: Utils.pm,v 1.7 2003/08/15 02:40:15 don Exp $

=pod

=head1 NAME

 CGI::Utils - Utilities for retrieving information through the
 Common Gateway Interface

=head1 SYNOPSIS

 use CGI::Utils;
 my $utils = CGI::Utils->new;

=head1 DESCRIPTION

 This module provides an object-oriented interface for retrieving
 information provided by the Common Gateway Interface, as well as
 url-encoding and decoding values. For example, CGI has a utility
 for escaping HTML, but no public interface for url-encoding a
 value or for taking a hash of values and returning a url-encoded
 query string suitable for passing to a CGI script. This module
 does that, as well as provide methods for creating a
 self-referencing url, converting relative urls to absolute,
 adding CGI parameters to the end of a url, etc.  Please see the
 METHODS section below for more detailed descriptions of
 functionality provided by this module.

=head1 METHODS

=cut

use strict;

{   package CGI::Utils;

    use vars qw($VERSION);
    
    BEGIN {
        $VERSION = 0.01; # update below in POD as well
    }

    sub new {
        my ($proto) = @_;
        my $self = bless {}, ref($proto) || $proto;
        return $self;
    }

=head2 urlEncode($str)

 Returns the fully URL-encoded version of the given string.  It
 does not convert space characters to '+' characters.

=cut
    sub urlEncode {
        my ($self, $str) = @_;
        $str =~ s{([^A-Za-z0-9_])}{sprintf("%%%02x", ord($1))}eg;
        return $str;
    }

=head2 urlDecode($url_encoced_str)

 Returns the decoded version of the given URL-encoded string.

=cut
    sub urlDecode {
        my ($self, $str) = @_;
        $str =~ tr/+/ /;
        $str =~ s|%([A-Fa-f0-9]{2})|chr(hex($1))|eg;
        return $str;
    }

=head2 urlEncodeVars($var_hash, $sep)

 Takes a hash of name/value pairs and returns a fully URL-encoded
 query string suitable for passing in a URL.  By default, uses
 the newer separator, a semicolon, as recommended by the W3C.  If
 you pass in a second argument, it is used as the separator
 between key/value pairs.

=cut
    sub urlEncodeVars {
        my ($self, $var_hash, $sep) = @_;
        $sep = ';' if $sep eq '';
        my @pairs;
        foreach my $key (keys %$var_hash) {
            my $val = $$var_hash{$key};
            my $ref = ref($val);
            if ($ref eq 'ARRAY' or $ref =~ /=ARRAY/) {
                push @pairs, map { $self->urlEncode($key) . "=" . $self->urlEncode($_) } @$val;
            } else {
                push @pairs, $self->urlEncode($key) . "=" . $self->urlEncode($val);
            }
        }

        return join($sep, @pairs);
    }

=head2 urlDecodeVars($query_string)

 Takes a URL-encoded query string, decodes it, and returns a
 reference to a hash of name/value pairs.  For multivalued
 fields, the value is an array of values.

=cut
    sub urlDecodeVars {
        my ($self, $query) = @_;
        my $var_hash = {};
        my @pairs = split /[;&]/, $query;
        
        foreach my $pair (@pairs) {
            my ($name, $value) = split /=/, $pair, 2;
            if (exists($$var_hash{$name})) {
                my $this_val = $$var_hash{$name};
                if (ref($this_val) eq 'ARRAY') {
                    push @$this_val, $value;
                } else {
                    $$var_hash{$name} = [ $this_val, $value ];
                }
            } else {
                $$var_hash{$name} = $value;
            }
        }
        
        return $var_hash;
    }

=head2 getSelfRefHostUrl()

 Returns a url referencing top level directory in the current
 domain, e.g., http://mydomain.com

=cut
    sub getSelfRefHostUrl {
        my ($self) = @_;
        my $scheme = $ENV{HTTPS} eq 'on' ? 'https' : 'http';
        return "$scheme://$ENV{HTTP_HOST}";
    }

=head2 getSelfRefUrl()

 Returns a url referencing the current script (without any query
 string).

=cut
    sub getSelfRefUrl {
        my ($self) = @_;
        return $self->getSelfRefHostUrl . $ENV{SCRIPT_NAME};
    }

=head2 getSelfRefUrlWithQuery()

 Returns a url referencing the current script along with any
 query string parameters passed via a GET method.

=cut
    sub getSelfRefUrlWithQuery {
        my ($self) = @_;

        return $self->getSelfRefHostUrl . $ENV{REQUEST_URI};
    }

=head2 getSelfRefUrlDir()

 Returns a url referencing the directory part of the current url.

=cut
    sub getSelfRefUrlDir {
        my ($self) = @_;
        my $url = $self->getSelfRefUrl;
        $url =~ s{^(.+?)\?.*$}{$1};
        $url =~ s{/[^/]+$}{};
        return $url;
    }

=head2 addParamsToUrl($url, $param_hash)

 Takes a url and reference to a hash of parameters to be added
 onto the url as a query string and returns a url with those
 parameters.  It checks whether or not the url already contains a
 query string and modifies it accordingly.  If you want to add a
 multivalued parameter, pass it as a reference to an array
 containing all the values.

=cut
    sub addParamsToUrl {
        my ($self, $url, $param_hash) = @_;
        my $sep = ';';
        if ($url =~ /^([^?]+)\?(.*)$/) {
            my $query = $2;
            # if query uses & for separator, then keep it consistent
            if ($query =~ /\&/) {
                $sep = '&';
            }
            $url .= $sep unless $url =~ /\?$/;
        } else {
            $url .= '?';
        }

        $url .= $self->urlEncodeVars($param_hash, $sep);
        return $url;
    }

=head2 getParsedCookies()

 Parses the cookies passed to the server.  Returns a hash of
 key/value pairs representing the cookie names and values.

=cut
    sub getParsedCookies {
        my ($self) = @_;
        my %cookies = map { (split(/=/, $_, 2)) } split(/;\s*/, $ENV{HTTP_COOKIE});
        return \%cookies;
    }
    
}

1;

__END__

=pod

=head1 AUTHOR

 Don Owens <don@owensnet.com>

=head1 COPYRIGHT

 Copyright (c) 2003 Don Owens

 All rights reserved. This program is free software; you can
 redistribute it and/or modify it under the same terms as Perl
 itself.

=head1 VERSION

 0.01

=cut
