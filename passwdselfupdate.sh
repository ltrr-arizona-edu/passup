#!/bin/sh
#------------------------------------------------------------------------------
#
#  passwdselfupdate.sh: rotate a password using the Stache API.
#
# Returns:
#   0 on success, 1 on any error.
#
# Required environment variables
# - PASSUP_KEY_READ The endpoint-specific API key for reading an entry
# - PASSUP_KEY_EDIT The endpoint-specific API key for editing an entry
# - PASSUP_ENTRY_DATA_READ Entry-data-read API endpoint
# - PASSUP_ENTRY_DATA_EDIT Entry-data-edit API endpoint
#------------------------------------------------------------------------------

set -e

#------------------------------------------------------------------------------
# Optional environment variables with simple defaults.

# The Stache server host name
: "${PASSUP_SERVER:=stache.arizona.edu}"

#------------------------------------------------------------------------------
# Utility definitions.

errorexit () {
  echo "** $1." >&2
  exit 1
}

# Show progress on STDERR, unless explicitly quiet.
if [ -z "$PASSUP_QUIET" ]; then
  logmessage () {
    echo "$1..." >&2
  }
  normalexit () {
    echo "$1." >&2
    exit 0
  }
else
  logmessage () {
    return
  }
  normalexit () {
    exit 0
  }
fi

#------------------------------------------------------------------------------
# Emit a random password, with character class constraints, on standard output.

if command -v pwgen > /dev/null ; then
  emitpasswd () {
    pwgen -c -n -r \\ -s -y 32 1
  }
elif command -v apg > /dev/null ; then
  emitpasswd () {
    apg -a 1 -E \\ -n 1 -m 32
  }
elif command -v openssl > /dev/null ; then
  emitpasswd () {
    while p=$(openssl rand -base64 33); do 
      echo "$p" | grep -q '[0-9]' || continue
      echo "$p" | grep -q '[A-Z]' || continue
      echo "$p" | grep -q '[a-z]' || continue
      echo "$p" | grep -q '[+/]' || continue
      break
    done
    echo "$p"
  }
else
  errorexit "Depends on pwgen or apg or Openssl to generate password of pseudo-random bytes"
fi

#------------------------------------------------------------------------------
# Initial sanity checking.

command -v curl > /dev/null \
  || errorexit "This reqires curl to access the Stache API endpoints"
command -v jq > /dev/null \
  || errorexit "This reqires the jq command-line JSON processor"
[ -n "$PASSUP_KEY_READ" ] \
  || errorexit "No API key specified for reading"
[ -n "$PASSUP_KEY_EDIT" ] \
  || errorexit "No API key specified for editing"
[ -n "$PASSUP_ENTRY_DATA_READ" ] \
  || errorexit "No Entry-data-read API endpoint specified"
[ -n "$PASSUP_ENTRY_DATA_EDIT" ] \
  || errorexit "No Entry-data-edit API endpoint specified"

#------------------------------------------------------------------------------
# Read the old contents of the Stache entry.

readendpoint='Entry-data-read API endpoint'
readfail='Failed to read the existing Stache entry'
resp=$(curl -s -S -H "X-STACHE-KEY: ${PASSUP_KEY_READ}" "https://${PASSUP_SERVER}${PASSUP_ENTRY_DATA_READ}")
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "${readfail}, curl returned '${err}'"
[ -n "$resp" ] || \
  errorexit "${readfail}, empty response from ${readendpoint}"
echo "$resp" | grep -v -q 'message'
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "${readfail}, ${readendpoint} responded ${resp}"
flatresp=$(echo "$resp" | tr '\n' ' ')
nickname=$(echo "$flatresp" | jq .nickname)
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "${readfail}, could not parse the ${readendpoint} response as JSON"
[ -n "$nickname" ] || \
  errorexit "${readfail}, ${readendpoint} did not provide the nickname"
oldpass=$(echo "$flatresp" | jq -r .secret)
[ -n "$oldpass" ] || \
  errorexit "${readfail}, ${readendpoint} did not provide the old password"
logmessage "${readendpoint} provided the existing Stache entry data"

#------------------------------------------------------------------------------
# Reset the password.

newpass=$(emitpasswd)
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "Failed to generate password: status '${err}'"
timestamp=$(date)
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "Failed to obtain a time stamp: status '${err}'"
printf '%s\n%s\n%s\n' "$oldpass" "$newpass" "$newpass" | passwd
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "Failed to update the local password: status '${err}'"

#------------------------------------------------------------------------------
# Update the contents of the Stache entry with new data.

request=$(echo "$flatresp" | jq --arg secret "$newpass" --arg memo "$timestamp" '{nickname, purpose, $secret, $memo}')
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "Could not create the updated JSON data: status '${err}'"
editendpoint='Entry-data-edit API endpoint'
editfail='Failed to edit the existing Stache entry'
resp=$(curl -s -S -X POST -H "X-STACHE-KEY: ${PASSUP_KEY_EDIT}" -H "Content-Type: application/json" -d "$request" "https://${PASSUP_SERVER}${PASSUP_ENTRY_DATA_EDIT}")
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "${editfail}, curl returned '${err}'"
[ -n "$resp" ] || \
  errorexit "${editfail}, empty response from ${editendpoint}"
echo "$resp" | grep -v -q 'message'
err="$?"
[ "$err" -eq 0 ] || \
  errorexit "${editfail}, ${editendpoint} responded ${resp}"
logmessage "${editendpoint} updated the Stache entry data"
normalexit "OK"
