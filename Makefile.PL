#!/usr/bin/perl

# Creation date: 2003-08-13 20:59:11
# Authors: Don
# Change log:
# $Id: Makefile.PL,v 1.2 2003/09/05 14:44:34 don Exp $

use strict;
use Carp;

# main
{
    local($SIG{__DIE__}) = sub { &Carp::cluck(); exit 0 };

    use ExtUtils::MakeMaker;

    WriteMakefile(
                  NAME => 'CGI::Utils',
                  DISTNAME => 'CGI-Utils',
                  VERSION_FROM => 'Utils.pm',
                  ABSTRACT => 'CGI utilities',
                  AUTHOR => 'DON OWENS <don@owensnet.com>',
                  PM => { 'Utils.pm' => '$(INST_LIBDIR)/Utils.pm',
                          'Utils/UploadFile.pm' => '$(INST_LIBDIR)/Utils/UploadFile.pm',
                        },
                  dist => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
                  DIR => [],
                  EXE_FILES => [],
                  );


}

exit 0;

###############################################################################
# Subroutines

