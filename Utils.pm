# -*-perl-*-
# Creation date: 2003-08-13 20:23:50
# Authors: Don
# Change log:
# $Id: Utils.pm,v 1.41 2004/03/29 07:37:07 don Exp $

# Copyright (c) 2003-2004 Don Owens

# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.

=pod

=head1 NAME

 CGI::Utils - Utilities for retrieving information through the
 Common Gateway Interface

=head1 SYNOPSIS

 use CGI::Utils;
 my $utils = CGI::Utils->new;

 my $fields = $utils->vars; # or $utils->Vars
 my $field1 = $$fields{field1};

     or

 my $field1 = $utils->param('field1');


 # File uploads
 my $file_handle = $utils->param('file0'); # or $$fields{file0};
 my $file_name = "$file_handle";  

=head1 DESCRIPTION

 This module can be used almost as a drop-in replacement for
 CGI.pm for those of you who do not use the HTML generating
 features of CGI.pm

 This module provides an object-oriented interface for retrieving
 information provided by the Common Gateway Interface, as well as
 url-encoding and decoding values, and parsing CGI
 parameters. For example, CGI has a utility for escaping HTML,
 but no public interface for url-encoding a value or for taking a
 hash of values and returning a url-encoded query string suitable
 for passing to a CGI script. This module does that, as well as
 provide methods for creating a self-referencing url, converting
 relative urls to absolute, adding CGI parameters to the end of a
 url, etc.  Please see the METHODS section below for more
 detailed descriptions of functionality provided by this module.

 File uploads via the multipart/form-data encoding are supported.
 The parameter for the field name corresponding to the file is a
 file handle that, when evaluated in string context, returns the
 name of the file uploaded.  To get the contents of the file,
 just read from the file handle.

=head1 METHODS

=cut

# TODO
# work under mod_perl 1 and 2
# cache values like parsed cookies
# NPH stuff for getHeader()

use strict;

{   package CGI::Utils;

    use vars qw($VERSION @ISA @EXPORT_OK @EXPORT %EXPORT_TAGS);

    use CGI::Utils::UploadFile;
    
    BEGIN {
        $VERSION = '0.06'; # update below in POD as well
    }
    
    require Exporter;
    @ISA = 'Exporter';
    @EXPORT = ();
    @EXPORT_OK = qw(urlEncode urlDecode urlEncodeVars urlDecodeVars getSelfRefHostUrl
                    getSelfRefUrl getSelfRefUrlWithQuery getSelfRefUrlDir addParamsToUrl
                    getParsedCookies escapeHtml escapeHtmlFormValue convertRelativeUrlWithParams
                    convertRelativeUrlWithArgs getSelfRefUri);
    $EXPORT_TAGS{all_utils} = [ qw(urlEncode urlDecode urlEncodeVars urlDecodeVars
                                   getSelfRefHostUrl
                                   getSelfRefUrl getSelfRefUrlWithQuery getSelfRefUrlDir
                                   addParamsToUrl getParsedCookies escapeHtml escapeHtmlFormValue
                                   convertRelativeUrlWithParams convertRelativeUrlWithArgs
                                   getSelfRefUri)
                              ];

=pod

=head2 new()

 Returns a new CGI::Utils object.

=cut
    sub new {
        my ($proto, $args) = @_;
        $args = {} unless ref($args) eq 'HASH';
        my $self = { _params => {}, _param_order => [], _upload_info => {},
                   _max_post_size => $$args{max_post_size} };
        bless $self, ref($proto) || $proto;
        return $self;
    }

=pod

=head2 urlEncode($str)

 Returns the fully URL-encoded version of the given string.  It
 does not convert space characters to '+' characters.

=cut
    sub urlEncode {
        my ($self, $str) = @_;
        $str =~ s{([^A-Za-z0-9_])}{sprintf("%%%02x", ord($1))}eg;
        return $str;
    }

=pod

=head2 urlDecode($url_encoced_str)

 Returns the decoded version of the given URL-encoded string.

=cut
    sub urlDecode {
        my ($self, $str) = @_;
        $str =~ tr/+/ /;
        $str =~ s|%([A-Fa-f0-9]{2})|chr(hex($1))|eg;
        return $str;
    }

=pod

=head2 urlEncodeVars($var_hash, $sep)

 Takes a hash of name/value pairs and returns a fully URL-encoded
 query string suitable for passing in a URL.  By default, uses
 the newer separator, a semicolon, as recommended by the W3C.  If
 you pass in a second argument, it is used as the separator
 between key/value pairs.

=cut
    sub urlEncodeVars {
        my ($self, $var_hash, $sep) = @_;
        $sep = ';' unless defined $sep;
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

=pod

=head2 urlDecodeVars($query_string)

 Takes a URL-encoded query string, decodes it, and returns a
 reference to a hash of name/value pairs.  For multivalued
 fields, the value is an array of values.  If called in array
 context, it returns a reference to a hash of name/value pairs,
 and a reference to an array of field names in the order they
 appear in the query string.

=cut
    sub urlDecodeVars {
        my ($self, $query) = @_;
        my $var_hash = {};
        my @pairs = split /[;&]/, $query;
        my $var_order = [];
        
        foreach my $pair (@pairs) {
            my ($name, $value) = map { $self->urlDecode($_) } split /=/, $pair, 2;
            if (exists($$var_hash{$name})) {
                my $this_val = $$var_hash{$name};
                if (ref($this_val) eq 'ARRAY') {
                    push @$this_val, $value;
                } else {
                    $$var_hash{$name} = [ $this_val, $value ];
                }
            } else {
                $$var_hash{$name} = $value;
                push @$var_order, $name;
            }
        }
        
        return wantarray ? ($var_hash, $var_order) : $var_hash;
    }

=head2 escapeHtml($text)

 Escapes the given text so that it is not interpreted as HTML.

=cut
    # added for v0.05
    sub escapeHtml {
        my ($self, $text) = @_;
        return undef unless defined $text;
        
        $text =~ s/\&/\&amp;/g;
        $text =~ s/</\&lt;/g;
        $text =~ s/>/\&gt;/g;
        $text =~ s/\"/\&quot;/g;
        $text =~ s/\$/\&dol;/g;

        return $text;
    }

=head2 escapeHtmlFormValue($text)

 Escapes the given text so that it is valid to put in a form
 field.

=cut
    # added for v0.05
    sub escapeHtmlFormValue {
        my ($self, $str) = @_;
        $str =~ s/\"/&quot;/g;
        $str =~ s/>/&gt;/g;
        $str =~ s/</&lt;/g;
        
        return $str;
    }


=pod

=head2 getSelfRefHostUrl()

 Returns a url referencing top level directory in the current
 domain, e.g., http://mydomain.com

=cut
    sub getSelfRefHostUrl {
        my ($self) = @_;
        my $https = $ENV{HTTPS};
        my $scheme = (defined($https) and lc($https) eq 'on') ? 'https' : 'http';
        $scheme = 'https' if defined($ENV{SERVER_PORT}) and $ENV{SERVER_PORT} == 443;
        return "$scheme://$ENV{HTTP_HOST}";
    }

=pod

=head2 getSelfRefUrl()

 Returns a url referencing the current script (without any query
 string).

=cut
    sub getSelfRefUrl {
        my ($self) = @_;
        # FIXME: make this work under mod perl 1 & 2
        return $self->getSelfRefHostUrl . $self->getSelfRefUri;
    }

=pod

=head2 getSelfRefUri()

 Returns the current URI.

=cut
    sub getSelfRefUri {
        my ($self) = @_;
        my $uri = $ENV{REQUEST_URI};
        $uri =~ s/^(.*?)\?.*$/$1/;
        return $uri;
    }

=pod

=head2 getSelfRefUrlWithQuery()

 Returns a url referencing the current script along with any
 query string parameters passed via a GET method.

=cut
    sub getSelfRefUrlWithQuery {
        my ($self) = @_;

        return $self->getSelfRefHostUrl . $ENV{REQUEST_URI};
    }

=pod

=head2 getSelfRefUrlWithParams($params)

 Returns a url reference the current script along with the given
 hash of parameters added onto the end of url as a query string.

=cut
    # added for 0.06
    sub getSelfRefUrlWithParams {
        my ($self, $args) = @_;

        return $self->addParamsToUrl($self->getSelfRefUrl, $args);
    }

=pod

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

=pod

=head2 convertRelativeUrlWithParams($relative_url, $params)

 Converts a relative URL to an absolute one based on the current
 URL, then adds the parameters in the given hash $params as a
 query string.

=cut
    # Takes $rel_url as a url relative to the current directory,
    # e.g., a script name, and adds the given cgi params to it.
    # added for v0.05
    sub convertRelativeUrlWithParams {
        my ($self, $rel_url, $args) = @_;
        my $host_url = $self->getSelfRefHostUrl;
        my $uri = $self->getSelfRefUri;
        $uri =~ s{^(.+?)\?.*$}{$1};
        $uri =~ s{/[^/]+$}{};

        if ($rel_url =~ m{^/}) {
            $uri = $rel_url;
        } else {
            while ($rel_url =~ m{^\.\./}) {
                $rel_url =~ s{^\.\./}{}; # pop dir off front
                $uri =~ s{/[^/]+$}{}; # pop dir off end
            }
            $uri .= '/' . $rel_url;
        }

        return $self->addParamsToUrl($host_url . $uri, $args);
    }
    *convertRelativeUrlWithArgs = \&convertRelativeUrlWithParams;

=pod

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

    sub _getRawCookie {
        return $ENV{HTTP_COOKIE} || $ENV{COOKIE} || '';
    }

=pod

=head2 getParsedCookies()

 Parses the cookies passed to the server.  Returns a hash of
 key/value pairs representing the cookie names and values.

=cut
    sub getParsedCookies {
        my ($self) = @_;
        my %cookies = map { (map { $self->urlDecode($_) } split(/=/, $_, 2)) }
            split(/;\s*/, $self->_getRawCookie);
        return \%cookies;
    }

    # added for v0.06
    # for compatibility with CGI.pm
    # may want to create an object here
    sub cookie {
        my ($self, @args) = @_;
        my $map_list = [ 'name', [ 'value', 'values' ], 'path', 'expires', 'domain', 'secure' ];
        my $params = $self->_parse_sub_params($map_list, \@args);
        if (exists($$params{value})) {
            return $params;
        } else {
            my $cookies = $self->getParsedCookies;
            if ($cookies and %$cookies) {
                return $$cookies{$$params{name}};
            }
            return '';
        }
        return $params;
    }

# =pod

# =head2 parse({ max_post_size => $max_bytes })

#  Parses the CGI parameters.  GET and POST (both url-encoded and
#  multipart/form-data encodings), including file uploads, are
#  supported.  If the request method is POST, you may pass a
#  maximum number of bytes to accept via POST.  This can be used to
#  limit the size of file uploads, for example.

# =cut
    sub parse {
        my ($self, $args) = @_;

        return 1 if $$self{_already_parsed};
        $$self{_already_parsed} = 1;

        $args = {} unless ref($args) eq 'HASH';

        # check for mod_perl - GATEWAY_INTERFACE =~ m{^CGI-Perl/}
        # check for PerlEx - GATEWAY_INTERFACE =~ m{^CGI-PerlEx}

        my $method = lc($ENV{REQUEST_METHOD});
        my $content_length = $ENV{CONTENT_LENGTH} || 0;

        if ($method eq 'post') {
            my $max_size = $$args{max_post_size} || $$self{_max_post_size};
            $max_size = 0 unless defined($max_size);
            if ($max_size > 0 and $content_length > $max_size) {
                return undef;
            }
        }

        if ($method eq 'post' and $ENV{CONTENT_TYPE} =~ m|^multipart/form-data|) {
            # FIXME: do mime parsing here for multipart/form-data
            if ($ENV{CONTENT_TYPE} =~ /boundary=(\"?)([^\";,]+)\1/) {
                my $boundary = $2;
                $self->_readMultipartData($boundary, $content_length, \*STDIN);
            } else {
                return undef;
            }
        } elsif ($method eq 'get' or $method eq 'head') {
            my $query_string = $ENV{QUERY_STRING};
            $self->_parseParams($query_string);
        } elsif ($method eq 'post') {
            my $query_string;
            $self->_readPostData(\*STDIN, \$query_string, $content_length) if $content_length > 0;
            $self->_parseParams($query_string);
            # FIXME: may want to append anything in query string
            # to POST data, so can do a post with an action that
            # contains a query string.
        }

        return 1;
    }

=pod

=head2 param($name)

 Returns the CGI parameter with name $name.  If called in array
 context, it returns an array.  In scalar context, it returns an
 array reference for multivalued fields, and a scalar for
 single-valued fields.

=cut
    sub param {
        my ($self, $name) = @_;
        $self->parse;
        
        if (scalar(@_) == 1 and wantarray()) {
            my $params = $$self{_params};
            my $order = $$self{_param_order};
            return grep { exists($$params{$_})  } @$order;
        }
        return undef unless defined($name);
        my $val = $$self{_params}{$name};

        if (wantarray()) {
            return ref($val) eq 'ARRAY' ? @$val : ($val);
        } else {
            return $val;
        }
    }

=pod

=head2 getVars($delimiter), vars($delimiter), Vars($delimiter)

 Also Vars() to be compatible with CGI.pm.  Returns a reference
 to a tied hash containing key/value pairs corresponding to each
 CGI parameter.  For multivalued fields, the value is an array
 ref, with each element being one of the values.  If you pass in
 a value for the delimiter, multivalued fields will be returned
 as a string of values delimited by the delimiter you passed in.

=cut
    sub getVars {
        my ($self, $multivalue_delimiter) = @_;
        if (defined($$self{_multivalue_delimiter}) and $$self{_multivalue_delimiter} ne '') {
            $multivalue_delimiter = $$self{_multivalue_delimiter}
                if not defined($multivalue_delimiter) or $multivalue_delimiter eq '';
        } elsif (defined($multivalue_delimiter) and $multivalue_delimiter ne '') {
            $$self{_multivalue_delimiter} = $multivalue_delimiter;
        }

        $self->parse;
        
        if (wantarray()) {
            my $params = $$self{_params};
            my %vars = %$params;
            foreach my $key (keys %vars) {
                if (ref($vars{$key}) eq 'ARRAY') {
                    if ($multivalue_delimiter ne '') {
                        $vars{$key} = join($multivalue_delimiter, @{$vars{$key}});
                    } else {
                        my @copy = @{$vars{$key}};
                        $vars{$key} = \@copy;
                    }
                }
            }
            return %vars;
        }
        
        my $vars = $$self{_vars_hash};
        return $vars if $vars;

        my %vars;
        tie %vars, 'CGI::Utils', $self;

        return \%vars;
    }
    *vars = \&getVars;
    *Vars = \&getVars;

=pod

# Other information provided by the CGI environment

=head2 getPathInfo(), path_info()

 Returns additional virtual path information from the URL (if
 any) after your script.

=cut
    # added for 0.06
    sub getPathInfo {
        my ($self) = @_;
        return $$self{_path_info} if defined($$self{_path_info});
        my $path_info = defined($ENV{PATH_INFO}) ? $ENV{PATH_INFO} : '';
        $$self{_path_info} = $path_info;
        return $path_info;
    }
    *path_info = \&getPathInfo;

=pod

=head2 getRequestMethod(), request_method()

 Return the request method, i.e., GET, POST, HEAD, or PUT.

=cut
    # added for 0.06
    sub getRequestMethod {
        return $ENV{REQUEST_METHOD};
    }
    *request_method = \&getRequestMethod;

=pod

=head2 getContentType(), content_type()

 Return the content type.

=cut
    # added for 0.06
    sub getContentType {
        return $ENV{CONTENT_TYPE};
    }
    *content_type = \&getContentType;

=pod

=head2 getPathTranslated(), path_translated()

 Return the physical path information if provided in the CGI environment.

=cut
    # added for 0.06
    sub getPathTranslated {
        return $ENV{PATH_TRANSLATED};
    }
    *path_translated = \&getPathTranslated;

=pod

=head2 getQueryString(), query_string()

 Return a query string created from the current parameters.

=cut
    # create a query string from current CGI params
    # added for 0.06
    sub getQueryString {
        my ($self) = @_;
        my $fields = $self->getVars;
        return $self->urlEncodeVars($fields);
    }
    *query_string = \&getQueryString;

=pod

=head2 getHeader(@args), header(@args)

 Generates HTTP headers.  Standard arguments are content_type,
 cookie, target, expires, and charset.  These should be passed as
 name/value pairs.  If only one argument is passed, it is assumed
 to be the 'content_type' argument.  If no values are passed, the
 content type is assumed to be 'text/html'.  The charset defaults
 to ISO-8859-1.  A hash reference can also be passed.  E.g.,

     print $cgi_obj->getHeader({ content_type => 'text/html', expires => '+3d' });

 The names 'content-type', and 'type' are aliases for
 'content_type'.  The arguments may also be passed CGI.pm style
 with a '-' in front, e.g.

     print $cgi_obj->getHeader( -content_type => 'text/html', -expires => '+3d' );

=cut
    sub getHeader {
        my ($self, @args) = @_;
        my $arg_count = scalar(@args);
        if ($arg_count == 0) {
            return "Content-Type: text/html\r\n\r\n";
        }
        if ($arg_count == 1) {
            # content-type provided
            return "Content-Type: $args[0]\r\n\r\n";
        }

        my $map_list = [ [ 'type', 'content-type', 'content_type' ],
                         'status',
                         [ 'cookie', 'cookies' ],
                         'target', 'expires', 'nph', 'charset', 'attachment',
                       ];
        my $params = $self->_parse_sub_params($map_list, \@args);
        
        my $charset = $$params{charset} || 'ISO-8859-1';
        my $content_type = $$params{type};
        $content_type ||= 'text/html' unless defined($content_type);
        $content_type .= "; charset=$charset"
            if $content_type =~ /^text/ and $content_type !~ /\bcharset\b/;

        # FIXME: handle NPH stuff

        my $headers = [];
        push @$headers, "Status: $$params{status}" if defined($$params{status});
        push @$headers, "Window-Target: $$params{target}" if defined($$params{target});
        
        my $cookies = $$params{cookie};
        if (defined($cookies) and $cookies) {
            my $cookie_array = ref($cookies) eq 'ARRAY' ? $cookies : [ $cookies ];
            foreach my $cookie (@$cookie_array) {
                # handle plain strings as well as CGI::Cookie objects and hashes
                my $str = '';
                if (UNIVERSAL::isa($cookie, 'CGI::Cookie')) {
                    $str = $cookie->as_string;
                } elsif (ref($cookie) eq 'HASH') {
                    $str = $self->_createCookieStrFromHash($cookie);    
                } else {
                    $str = $cookie;
                }
                push @$headers, "Set-Cookie: $str" unless $str eq '';
            }
        }

        if (defined($$params{expires})) {
            my $expire = $self->_canonicalizeHttpDate($$params{expires});
            push @$headers, "Expires: $expire";
        }

        if (defined($$params{expires}) or (defined($cookies) and $cookies)) {
            push @$headers, "Date: " . $self->_canonicalizeHttpDate(0);
        }
        
        push @$headers, qq{Content-Disposition: attachment; filename="$$params{attachment}"}
            if defined($$params{attachment});
        push @$headers, "Content-Type: $content_type" if defined($content_type);

        # FIXME: make line endings work on windoze
        return join("\r\n", @$headers) . "\r\n\r\n";
    }
    *header = \&getHeader;

    sub _createCookieStrFromHash {
        my ($self, $hash) = @_;
        my $pairs = [];

        my $map_list = [ 'name', [ 'value', 'values' ], 'path', 'expires', 'domain', 'secure' ];
        my $params = $self->_parse_sub_params($map_list, [ $hash ]);

        my $value = $$params{value};
        if (my $ref = ref($value)) {
            if ($ref eq 'ARRAY') {
                $value = join('&', map { $self->urlEncode($_) } @$value);
            } elsif ($ref eq 'HASH') {
                $value = join('&', map { $self->urlEncode($_) } %$value);
            }
        } else {
            $value = $self->urlEncode($value);
        }
        push @$pairs, qq{$$params{name}=$value};

        my $path = $$params{path} || '/';
        push @$pairs, qq{path=$path};
        
        push @$pairs, qq{domain=$$params{domain}} if $$params{domain};

        if ($$params{expires}) {
            my $expire = $self->_canonicalizeCookieDate($$params{expires});
            push @$pairs, qq{expires=$expire};
        }

        push @$pairs, qq{secure} if $$params{secure};

        return join('; ', @$pairs);
    }
    
    sub _canonicalizeCookieDate {
        my ($self, $expire) = @_;
        return $self->_canonicalizeDate('-', $expire);
    }
    
    sub _canonicalizeHttpDate {
        my ($self, $expire) = @_;
        return $self->_canonicalizeDate(' ', $expire);
        
        my $time = $self->_get_expire_time_from_offset($expire);
        return $time unless $time =~ /^\d+$/;

        my $wdays = [ qw(Sun Mon Tue Wed Thu Fri Sat) ];
        my $months = [ qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec) ];
        
        my $sep = ' ';

        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
        $year += 1900 unless $year > 1000;
        return sprintf "%s, %02d$sep%s$sep%04d %02d:%02d:%02d GMT",
            $$wdays[$wday], $mday, $$months[$mon], $year, $hour, $min, $sec;
    }

    sub _canonicalizeDate {
        my ($self, $sep, $expire) = @_;
        my $time = $self->_get_expire_time_from_offset($expire);
        return $time unless $time =~ /^\d+$/;

        my $wdays = [ qw(Sun Mon Tue Wed Thu Fri Sat) ];
        my $months = [ qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec) ];

        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($time);
        $year += 1900 unless $year > 1000;
        return sprintf "%s, %02d$sep%s$sep%04d %02d:%02d:%02d GMT",
            $$wdays[$wday], $mday, $$months[$mon], $year, $hour, $min, $sec;

    }

    sub _get_expire_time_from_offset {
        my ($self, $offset) = @_;
        my $ret_offset = 0;
        if (not $offset or lc($offset) eq 'now') {
            $ret_offset = 0;
        } elsif ($offset =~ /^\d+$/) {
            return $offset;
        } elsif ($offset =~ /^([-+]?(?:\d+|\d*\.\d*))([mhdMy]?)/) {
            my $map = { 's' => 1,
                        'm' => 60,
                        'h' => 60 * 60,
                        'd' => 60 * 60 * 24,
                        'M' => 60 * 60 * 24 * 30,
                        'y' => 60 * 60 * 24 * 365,
                      };
            $ret_offset = ($$map{$2} || 1) * $1;
        } else {
            $ret_offset = $offset;
        }

        return time() + $ret_offset;
    }
    
    # canonicalize parameters so we can be compatible with CGI.pm
    sub _parse_sub_params {
        my ($self, $map_list, $args) = @_;

        my $arg_count = scalar(@$args);
        return {} if $arg_count == 0;

        my $hash;
        if ($arg_count == 1) {
            if (ref($$args[0]) eq 'HASH') {
                $hash = $$args[0];
            } else {
                if (ref($$map_list[0]) eq 'ARRAY') {
                    return { $$map_list[0][0] => $$args[0] };
                } else {
                    return { $$map_list[0] => $$args[0] };
                }
            }
        } else {
            $hash = { @$args };
        }

        my $return_hash = {};
        foreach my $key (keys %$hash) {
            my $orig_key = $key;
            $key =~ s/^-{1,2}//;
            $key = lc($key);
            foreach my $e (@$map_list) {
                if (ref($e) eq 'ARRAY') {
                    my $canon_key = $$e[0];
                    foreach my $e2 (@$e) {
                        if ($e2 eq $key) {
                            $$return_hash{$canon_key} = $$hash{$orig_key};
                        }
                    }
                } else {
                    if ($e eq $key) {
                        $$return_hash{$e} = $$hash{$orig_key};
                    }
                }
            }
        }

        return $return_hash;
    }
    
    sub TIEHASH {
        my ($proto, $obj) = @_;
        return $obj;
    }

    sub STORE {
        my ($self, $key, $val) = @_;
        my $params = $$self{_params};
        # FIXME: memory leak here - need to compress the array if has empty slots
        # push(@{$$self{_param_order}}, $key) unless exists($$params{$key});
        $$params{$key} = $val;
    }

    sub FETCH {
        my ($self, $key) = @_;
        my $params = $$self{_params};
        my $val = $$params{$key};
        if (ref($val) eq 'ARRAY') {
            my $delimiter = $$self{_multivalue_delimiter};
            $val = join($delimiter, @$val) unless $delimiter eq '';
        }
        return $val;
    }

    sub FIRSTKEY {
        my ($self) = @_;
        my @keys = keys %{$$self{_params}};
        $$self{_keys} = \@keys;
        return shift @keys;
    }

    sub NEXTKEY {
        my ($self) = @_;
        return shift(@{$$self{_keys}});
    }

    sub EXISTS {
        my ($self, $key) = @_;
        my $params = $$self{_params};
        return exists($$params{$key});
    }

    sub DELETE {
        my ($self, $key) = @_;
        my $params = $$self{_params};
        delete $$params{$key};
    }

    sub CLEAR {
        my ($self) = @_;
        %{$$self{_params}} = ();
    }

    sub _parseParams {
        my ($self, $query_string) = @_;
        ($$self{_params}, $$self{_param_order}) = $self->urlDecodeVars($query_string);
    }

    sub _readPostData {
        my ($self, $fh, $buf, $len) = @_;
        return CORE::read($fh, $$buf, $len);
    }

    sub _readMultipartData {
        my ($self, $boundary, $content_length, $fh) = @_;
        my $line;
        my $eol = $self->_getEndOfLineSeq;
        my $end_char = substr($eol, -1, 1);
        my $buf;
        my $len = 1024;
        my $amt_read = 0;
        my $sep = "--$boundary$eol";

        my $params = {};
        my $param_order = [];

        while (my $size = $self->_read($fh, $buf, $len, 0, $end_char)) {
            $amt_read += $size;
            if ($buf eq $sep) {
                last;
            }
            last unless $amt_read < $content_length;
        }

        while ($amt_read < $content_length) {
            my ($headers, $amt) = $self->_readMultipartHeader($fh);
            $amt_read += $amt;
            my $disp = $$headers{'content-disposition'};
            my ($type, @fields) = split /;\s*/, $disp;
            my %disp_fields = map { s/^(\")(.+)\1$/$2/; $_ } map { split(/=/, $_, 2) } @fields;
            my $name = $disp_fields{name};
            my ($body, $body_size) = $self->_readMultipartBody($boundary, $fh, $headers, \%disp_fields);
            $amt_read += $body_size;

            next if $name eq '';

            if (exists($$params{$name})) {
                my $val = $$params{$name};
                if (ref($val) eq 'ARRAY') {
                    push @$val, $body;
                } else {
                    my $array = [ $val, $body ];
                    $$params{$name} = $array;
                }
            } else {
                $$params{$name} = $body;
                push @$param_order, $name;
            }

        }

        $$self{_params} = $params;
        $$self{_param_order} = $param_order;

        return 1;
    }

    sub _readMultipartBody {
        my ($self, $boundary, $fh, $headers, $disposition_fields) = @_;

        local($^W) = 0; # turn off lame warnings
        
        if ($$disposition_fields{filename} ne '') {
            return $self->_readMultipartBodyToFile($boundary, $fh, $headers, $disposition_fields);
        }
        
        my $amt_read = 0;
        my $eol = $self->_getEndOfLineSeq;
        my $end_char = substr($eol, -1, 1);
        my $buf;
        my $body;

        while (my $size = $self->_read($fh, $buf, 4096, 0, $end_char)) {
            $amt_read += $size;
            if (substr($buf, -1, 1) eq $end_char and $buf =~ /^--$boundary(?:--)?$eol$/
                and $body =~ /$eol$/
               ) {
                $body =~ s/$eol$//;
                last;
            }
            $body .= $buf;
        }

        return wantarray ? ($body, $amt_read) : $body;
    }

    sub _readMultipartBodyToFile {
        my ($self, $boundary, $fh, $headers, $disposition_fields) = @_;

        my $amt_read = 0;
        my $body;
        my $eol = $self->_getEndOfLineSeq;
        my $end_char = substr($eol, -1, 1);
        my $buf = '';
        my $buf2 = '';

        my $file_name = $$disposition_fields{filename};
        my $info = { 'Content-Type' => $$headers{'content-type'} };
        $$self{_upload_info}{$file_name} = $info;

        my $out_fh = CGI::Utils::UploadFile->new_tmpfile($file_name);
        
        while (my $size = $self->_read($fh, $buf, 4096, 0, $end_char)) {
            $amt_read += $size;
            if (substr($buf, -1, 1) eq $end_char and $buf =~ /^--$boundary(?:--)?$eol$/
                and $buf2 =~ /$eol$/
               ) {
                $buf2 =~ s/$eol$//;
                $buf = '';
                print $out_fh $buf2;
                last;
            }
            print $out_fh $buf2;
            $buf2 = $buf;
            $buf = '';
        }
        if ($buf ne '') {
            print $out_fh $buf;
        }
        select((select($out_fh), $| = 1)[0]);
        seek($out_fh, 0, 0); # seek back to beginning of file
        
        return wantarray ? ($out_fh, $amt_read) : $out_fh;
    }

=pod

=head2 uploadInfo($file_name)

 Returns a reference to a hash containing the header information
 sent along with a file upload.

=cut
    # provided for compatibility with CGI.pm
    sub uploadInfo {
        my ($self, $file_name) = @_;
        $self->parse;
        return $$self{_upload_info}{$file_name};
    }

    sub _readMultipartHeader {
        my ($self, $fh) = @_;
        my $amt_read = 0;
        my $eol = $self->_getEndOfLineSeq;
        my $end_char = substr($eol, -1, 1);
        my $buf;
        my $header_str;
        while (my $size = $self->_read($fh, $buf, 4096, 0, $end_char)) {
            $amt_read += $size;
            last if $buf eq $eol;
            $header_str .= $buf;
        }

        my $headers = {};
        my $last_header;
        foreach my $line (split($eol, $header_str)) {
            if ($line =~ /^(\S+):\s*(.+)$/) {
                $last_header = lc($1);
                $$headers{$last_header} = $2;
            } elsif ($line =~ /^\s+/) {
                $$headers{$last_header} .= $eol . $line;
            }
        }

        return wantarray ? ($headers, $amt_read) : $headers;
    }

    sub _getEndOfLineSeq {
        return "\x0d\x0a"; # "\015\012" in octal
    }

    sub _read {
        my ($self, $fh, $buf, $len, $offset, $end_char) = @_;
        return '' if $len == 0;
        my $cur_len = 0;
        my $buffer;
        my $buf_ref = \$buffer;
        my $char;
        while (defined($char = CORE::getc($fh))) {
            $$buf_ref .= $char;
            $cur_len++;
            if ($char eq $end_char or $cur_len == $len) {
                if ($offset > 0) {
                    substr($_[2], $offset, $cur_len) = $$buf_ref;
                } else {
                    $_[2] = $$buf_ref;
                }
                return $cur_len;
            }
        }
        return 0;
    }

}

1;

__END__

=pod

=head1 EXPORTS

 You can export methods into your namespace in the usual way.
 All of the util methods are available for export, e.g.,
 getSelfRefUrl(), addParamsToUrl(), etc.  Beware, however, that
 these methods expect to be called as methods.  You can also use
 the tag :all_utils to import all of the util methods into your
 namespace.  This allows for incorporating these methods into
 your class without having to inherit from CGI::Utils.

=head1 AUTHOR

 Don Owens <don@owensnet.com>

=head1 COPYRIGHT

 Copyright (c) 2003-2004 Don Owens

 All rights reserved. This program is free software; you can
 redistribute it and/or modify it under the same terms as Perl
 itself.

=head1 VERSION

 0.06

=cut
