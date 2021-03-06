#!/usr/bin/ksh
# alimit.sh (c) 2012 <s@ctrlc.hu>

#  This is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.

# monitors ncsa logfiles for requests to *limited* files which after
# exceeding their TTL are deleted from the disk
# useful for sharing files for a limited amount of downloads

# to alimit a file create a .<filename>.alimit file containing the
# number of allowed (and successful) downloads

# limitations, only handles 200 requests, continuation, redirects, etc
# are not covered

# example
# create a file and set the limit to 3 downloads
# sudo sh -c 'rm alimit.log; echo 'asdf' >/var/www/limited; echo 3 >/var/www/.limited.alimit; ./alimit.sh
# execute 4 times:
# curl localhost/limited; curl localhost/.limited.alimit
# check out the log
# cat alimit.log

# defaults
docroot=/var/www
logfile=/var/log/nginx/access.log
skippath='' # for aliased locations contains string to skip, e.g. '/~*/'

# set skippath, docroot, logfile in these:
source /etc/putbagrc 2>/dev/null
source ~/.putbagrc 2>/dev/null
source .putbagrc 2>/dev/null

while getopts a:l:r: opt
do
    case "$opt" in
      a)  skippath="$OPTARG";;
      l)  logfile="$OPTARG";;
      r)  docroot="$OPTARG";;
      \?)		# unknown flag
      	  echo >&2 \
	  "usage: $0 [-r <docroot>] [-a <skippath>] [-l <logfile>] [file ...]"
	  exit 1;;
    esac
done
shift `expr $OPTIND - 1`

function urldecode {
    arg=$(head -1)
    i=0
    while [[ $i -lt ${#arg} ]]; do
        p0=${arg:$i:1}
        if [ "x$p0" = "x%" ]; then
            #p1=${arg:$((i+1)):1}
            #p2=${arg:$((i+2)):1}
            p=${arg:$((i+1)):2}
            printf "\x$p"
            #printf "\x$p1$p2"
            i=$((i+3))
        else
            echo -n $p0
            i=$((i+1))
        fi
    done
}

tail -F -n 0 "$logfile" | while read entry; do
    # only handle 200 OK responses
    error=$(print "$entry" | sed 's/.*\] "[^"]*" \([0-9]*\).*/\1/')
    [[ "$error" != "200" ]] && continue

    # extract path and filename from request
    req=$(print "$entry" | sed -r 's/.*]\s"([^ ]+)\s.*/\1/')
    [[ "x$req" != "xGET" && "x$req" != "xPOST" ]] && continue
    rpath=$(print "$entry" | sed -r 's/.*] "'$req' (.*) HTTP\/[0-9.]*" .*/\1/' | urldecode)

    # not with skippath prefix
    [[ "${rpath##$skippath}" == "$rpath" ]] && continue
    [[ -e "$docroot${rpath##$skippath}" ]] || {
        print "$(date --rfc-3339=ns) WARN not found: $rpath $entry"
        continue
    }
    filename="${rpath##*/}"
    directory="${rpath%%/*}"
    [[ -n "$skippath" ]] && directory="${directory##$skippath}"
    # if alimited file
    limitfile="$docroot$directory/.$filename.alimit"
    [[ -r "$limitfile" ]] && {
        size=$(print "$entry" | sed 's/.*\] "[^"]*" [0-9]* \([0-9]*\).*/\1/')
        # ignore incomplete downloads
        [[ "$size" -lt $(stat -c "%s" "$docroot$directory/$filename") ]] && continue
        ttl=$(( $(head -1 "$limitfile") - 1))
        [[ "$ttl" -gt 0 ]] && {
            # alimited file hit, decrease ttl
            print "$ttl" >"$limitfile";
            print "$(date --rfc-3339=ns) HIT $ttl $rpath $entry"
        }
        [[ "$ttl" -eq 0 ]] && {
            # ttl exceeded wipe file from disk
            tlimit="$docroot$directory/.$filename.tlimit"
            srm -fll "$docroot$directory/$filename" "$limitfile" "$tlimit" 2>/dev/null;
            print "$(date --rfc-3339=ns) KILL $rpath $entry"
        }
    }
done
