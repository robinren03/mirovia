#!/bin/bash

aclocal
autoheader
automake --force-missing --add-missing
autoconf
