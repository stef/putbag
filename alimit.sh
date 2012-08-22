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

docroot=${1:-/var/www}
logfile=${2:-/var/log/nginx/access.log}
skippath=$(cat skippath)

tail -F -n 0 "$logfile" | while read entry; do
    # only handle 200 OK responses
    error=$(print "$entry" | sed 's/.*\] "[^"]*" \([0-9]*\).*/\1/')
    [[ "$error" != "200" ]] && continue

    # extract path and filename from request
    req=$(print "$entry" | sed -r 's/.*]\s"([^ ]+)\s.*/\1/')
    [[ "x$req" != "xGET" && "x$req" != "xPOST" ]] && continue
    rpath=$(print "$entry" | sed -r 's/.*] "'$req' (.*) HTTP\/[0-9.]*" .*/\1/')

    [[ -f "$docroot${rpath##$skippath}" ]] || {
        print "$(date --rfc-3339=ns) WARN not found: $rpath $entry" >>alimit.log
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
        [[ "$size" -lt $(stat -c "%s" "$docroot$directory$filename") ]] && continue
        ttl=$(( $(head -1 "$limitfile") - 1))
        [[ "$ttl" -gt 0 ]] && {
            # alimited file hit, decrease ttl
            print "$ttl" >"$limitfile";
            print "$(date --rfc-3339=ns) HIT $ttl $rpath $entry" >>alimit.log
        }
        [[ "$ttl" -eq 0 ]] && {
            # ttl exceeded wipe file from disk
            tlimit="$docroot$directory/.$filename.tlimit"
            srm -fll "$docroot$directory$file" "$limitfile" "$tlimit";
            print "$(date --rfc-3339=ns) KILL $rpath $entry" >>alimit.log
        }
    }
done
