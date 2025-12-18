#!/bin/sh

###################
# jamf_smartgroup_to_advsearch.sh - create advanced search from existing smart groups
# https://github.com/gimmickyboot/Jamf-SmartGroup-to-AdvancedSearch
#
# v1.0 (19/12/2025)
###################
## uncomment the next line to output debugging to stdout
#set -x

###############################################################################
## variable declarations
# shellcheck disable=SC2034
ME=$(basename "$0")
# shellcheck disable=SC2034
BINPATH=$(dirname "$0")
logFile="${HOME}/Library/Logs/$(basename "${ME}" .sh).log"

###############################################################################
## function declarations

statMsg() {
  # function to send messages to the log file. send second arg to output to stdout
  # usage: statMsg "<message to send>" [ "" ]

  if [ $# -gt 1 ]; then
    # send message to stdout
    /bin/echo "$1"
  fi
  
  /bin/echo "$(/bin/date "+%Y-%m-%d %H:%M:%S"): $1" >> "${logFile}"

}

apiRead() {
  # $1 = endpoint, ie JSSResource/policies or api/v1/computers-inventory?section=GENERAL&page=0&page-size=100&sort=general.name%3Aasc
  # $2 = acceptType, ie json or xml, xml is default
  # usage: apiRead "JSSResource/computergroups/id/0" [ "json" ]
  
  if [ $# -eq 1 ]; then
    acceptType="xml"
  else
    acceptType="$2"
  fi
  /usr/bin/curl -s -X GET "${jssURL}${1}" -H "Accept: application/${acceptType}" -H "Authorization: Bearer ${apiToken}"

}

apiPost() {
  # $1 = endpoint, ie JSSResource/advancedmobiledevicesearches/id/0 or v1/categories/4/history
  # $2 = data
  # $3 = acceptType, ie json or xml, xml is default
  # usage: apiPost "JSSResource/computergroups/id/0" <data> [ "json" ]

  if [ $# -eq 2 ]; then
    contentType="xml"
  else
    contentType="$3"
  fi
  /usr/bin/curl -s -X POST "${jssURL}${1}" -H "Content-Type: application/${contentType}" -H "Authorization: Bearer ${apiToken}" --data "${2}"

}

checkPostResult(){
  # $1 - put result XML
  # $2 - name of the group
  # usage checkPostResult "<xml data> <group name>"

  if printf '%s\n' "${1}" | /usr/bin/xmllint --xpath 'string(//id)' - >/dev/null 2>&1; then
    statMsg "\"$2\" successfully added to advanced searches" ""
  else
    statMsg "\"$2\" failed to add to advanced searches " ""
  fi

}

processTokenExpiry() {
  # returns apiTokenExpiresEpochUTC
  # time is UTC!!!
  # usage: processTokenExpiry
  
  if [ "${apiUsername}" ]; then
    apiTokenExpiresLongUTC=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .expires | /usr/bin/awk -F . '{ print $1 }')
    apiTokenExpiresEpochUTC=$(/bin/date -u -j -f "%Y-%m-%dT%T" "${apiTokenExpiresLongUTC}" +"%s")
  else
    apiTokenExpiresInSec=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .expires_in)
    epochNowUTC=$(/bin/date -u '+%s')
    apiTokenExpiresEpochUTC=$((apiTokenExpiresInSec+epochNowUTC-15))
  fi

}

renewToken(){
  # renews a near expiring token
  # usage: renewToken

  if [ "${apiUsername}" ] && [ "${epochDiff}" -le 0 ]; then
    authTokenJson=$(/usr/bin/curl -s "${jssURL}api/v1/auth/token" -X POST -H "Authorization: Basic ${baseCreds}")
    apiToken=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .token)
  elif  [ "${apiUsername}" ] && [ "${epochDiff}" -le 30 ]; then
    authTokenJson=$(/usr/bin/curl -s -X POST "${jssURL}api/v1/auth/keep-alive" -H "Authorization: Bearer ${apiToken}")
    apiToken=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .token)
  else
    authTokenJson=$(/usr/bin/curl -s "${jssURL}api/oauth/token" -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=${clientID}" --data-urlencode "grant_type=client_credentials" --data-urlencode "client_secret=${clientSecret}")
    apiToken=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .access_token)
  fi

  # process the token's expiry
  processTokenExpiry

}

checkToken() {
  # check the token expiry
  # usage: checkToken

  epochNowUTC=$(/bin/date -u +"%s")
  epochDiff=$((apiTokenExpiresEpochUTC - epochNowUTC))
  if [ "${epochDiff}" -le 0 ]; then
    statMsg "Token has expired. Renewing"
    renewToken
  elif [ "${epochDiff}" -lt 30 ]; then
    statMsg "Token nearing expiry (${epochDiff}s). Renewing"
    renewToken
  else
    statMsg "Token valid (${epochDiff}s left)"
  fi

}

destroyToken() {
  # destroys the token
  # usage: destroyToken

  if [ ! "${premExit}" ]; then
    statMsg "Destroying the token"
    responseCode=$(/usr/bin/curl -w "%{http_code}" -s -X POST "${jssURL}api/v1/auth/invalidate-token" -o /dev/null -H "Authorization: Bearer ${apiToken}")
    case "${responseCode}" in
      204)
        statMsg "Token has been destroyed"
        ;;

      401)
        statMsg "Token already invalid"
        ;;

      *)
        statMsg "An unknown error has occurred destroying the token"
        ;;
    esac

    authTokenRAW=""
    authTokenJson=""
    apiToken=""
    apiTokenExpiresEpochUTC="0"
  fi

}

clean_up(){

  destroyToken
  /bin/rm -f "${pairs_tmp}" 2>/dev/null

}

###############################################################################
## start the script here
trap clean_up EXIT HUP INT TERM

# jq is required. Check and exit if not present
if ! jqBin=$(command -v jq); then
  cat << EOF

ERROR: jq is required. Please install and try again.

EOF
  exit 1
fi

# check that we have enough args
if [ $# -ne 0 ]; then
  theGroupType="$1"
  if [ $# -eq 2 ]; then
    jssURL=$2
  fi
  # clear the terminal
  theGroupType=$(/bin/echo "${theGroupType}" | tr '[:lower:]' '[:upper:]')
  clear
else
  cat << EOF

Create an advanced seach, from a smart user, mobile device or computer group

  usage: ${ME} <type of static group> [ optional full JSS URL ]
  
  Types of static groups are user, mobile or computer

  The JSS URL is automatically detected from the Mac you run this on. If none found
  (or optionally provided) you will be prompted to enter one

  eg ${ME} user
     ${ME} user "https://myco.jamfcloud.com"

EOF
  premExit=1
  exit 1
fi

# verify we have a jssURL. Ask if we don't
if [ ! "${jssURL}" ]; then
  statMsg "No jssURL passed as an argument. Reading from this Mac"
  jssURL=$(/usr/libexec/PlistBuddy -c "Print :jss_url" /Library/Preferences/com.jamfsoftware.jamf.plist)
fi
until /usr/bin/curl --connect-timeout 5 -s "${jssURL}"; do
  /bin/echo ""
  statMsg "jssURL is invalid or none found on this Mac" ""
  printf "\nEnter a JSS URL, eg https://jss.jamfcloud.com:8443/ (leave blank to exit): "
  unset jssURL
  read -r jssURL
  if [ ! "${jssURL}" ]; then
    /bin/echo ""
    premExit=1
    exit 0
  fi
done

# make sure we have a trailing /
lastChar=$(/bin/echo "${jssURL}" | rev | /usr/bin/cut -c 1 -)
case "${lastChar}" in
  "/")
    /bin/echo "GOOD" >/dev/null 2>&1
    ;;

  *)
    jssURL="${jssURL}/"
    ;;
esac

/bin/echo ""
statMsg "jssURL ${jssURL} is valid. Continuing" ""

while : ; do
  /bin/echo ""
  printf "Choose the type of authentication, Username/password (U or u) or API roles and clients (R or r) (leave blank to exit): "
  read -r authChoice
  if [ ! "${authChoice}" ]; then
    /bin/echo ""
    premExit=1
    exit 0
  fi

  case "${authChoice}" in
    U|u)
      # get user creds and token
      while : ; do
        /bin/echo ""
        printf "Enter your API username (leave blank to exit): "
        read -r apiUsername
        if [ ! "${apiUsername}" ]; then
          /bin/echo ""
          premExit=1
          exit 0
        fi
        /bin/echo ""
        printf "Enter your API password (no echo): "
        stty -echo
        read -r apiPassword
        stty echo
        echo ""

        baseCreds=$(printf "%s:%s" "${apiUsername}" "${apiPassword}" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i -)

        # get the token
        authTokenRAW=$(/usr/bin/curl -s -w "%{http_code}" "${jssURL}api/v1/auth/token" -X POST -H "Authorization: Basic ${baseCreds}")
        authTokenJson=$(printf '%s' "${authTokenRAW}" | /usr/bin/sed -e '$s/...$//' )
        httpCode=$(printf '%s' "${authTokenRAW}" | /usr/bin/tail -c 3)
        case "${httpCode}" in
          200)
            statMsg "Authentication successful" ""
            statMsg "Token created successfully"

            # strip out the token
            apiToken=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .token)

            # process the token's expiry
            processTokenExpiry

            # unset apiPassword
            break 2
            ;;

          *)
            printf '\nError getting token. HTTP Status code: %s\n\nPlease try again.\n\n' "${httpCode}"
            premExit=1
            continue
            ;;
        esac
      done

      ;;

    R|r)
      statMsg "API roles and clients has been chosen" ""
      /bin/echo ""
      while : ; do
        printf "\nEnter your client id (leave blank to exit): "
        read -r clientID
        if [ ! "${clientID}" ]; then
          /bin/echo ""
          premExit=1
          exit 0
        fi

        printf "\nEnter your client secret (no echo): "
        stty -echo
        read -r clientSecret
        stty echo

        authTokenRAW=$(/usr/bin/curl -s -w "%{http_code}" "${jssURL}api/oauth/token" -H "Content-Type: application/x-www-form-urlencoded" --data-urlencode "client_id=${clientID}" --data-urlencode "grant_type=client_credentials" --data-urlencode "client_secret=${clientSecret}")
        authTokenJson=$(printf '%s' "${authTokenRAW}" | /usr/bin/sed -e '$s/...$//' )
        httpCode=$(printf '%s' "${authTokenRAW}" | /usr/bin/tail -c 3)
        case "${httpCode}" in
          200)
            /bin/echo ""
            /bin/echo "Token created successfully"

            # strip out the token
            apiToken=$(/bin/echo "${authTokenJson}" | "${jqBin}" -r .access_token)
            processTokenExpiry

            # unset clientSecret
            break 2
            ;;

          *)
            printf '\nError getting token. http error code is: %s\n\nPlease try again.\n\n' "${httpCode}"
            premExit=1
            continue
            ;;
        esac


      done
      ;;

       *)
        /bin/echo ""
        /bin/echo "Unknown choice. Please try again. Leave blank to exit."
        ;;
      esac
done

# get all of the available smart groups for the chose type
case ${theGroupType} in
  USER)
    theGroups=$(apiRead "JSSResource/usergroups" json | "${jqBin}" -r '.user_groups[] | select(.is_smart == true)| [.id, .name] | @tsv')
    ;;
    
  MOBILE|COMPUTER)
    theGroups=$(apiRead "api/v1/groups?page=0&page-size=100&sort=groupName%3Aasc&filter=groupType%3D%3D%22${theGroupType}%22" json | "${jqBin}" -r '.results[] | select(.smart == true) | [.groupJamfProId, .groupName] | @tsv')
    ;;
    
  *)
    /bin/echo "Unknown type. Exiting."
    exit 1
    ;;
esac

# build and display the menu
pairs_tmp=${TMPDIR:-/tmp}/pairs.$$
printf '%s\n' "${theGroups}" > "${pairs_tmp}"
count=$(/usr/bin/wc -l <"$pairs_tmp" | /usr/bin/awk '{print $1}')
[ "$count" -gt 0 ] || { printf 'No options\n' >&2; exit 1; }

cat << EOF

Groups are listed as "[Jamf ID] <Group name>"

EOF
/usr/bin/awk -F'\t' '{ printf "%d) [%s] %s\n", NR, $1, $2 > "/dev/stderr" }' "${pairs_tmp}"

while : ; do
  printf '\nEnter choice(s) (space-separated, 1-%s, q to quit): ' "${count}" >&2
  IFS= read -r choices || exit 1

  # Quit
  case "${choices}" in
    ''|q|Q)
      exit 1
      ;;
  esac

  valid=1
  selected_ids=""

  for choice in ${choices}; do
    case "${choice}" in
      *[!0-9]*)
        valid=0
        break
        ;;
    esac

  if [ "${choice}" -ge 1 ] && [ "${choice}" -le "${count}" ]; then
    id=$(/usr/bin/sed -n "${choice}p" "${pairs_tmp}" | /usr/bin/cut -f 1 -)
    selected_ids="${selected_ids}${id}
"
  else
    valid=0
    break
  fi
  done

  if [ "${valid}" -eq 1 ]; then
    break
  fi

  printf 'Invalid or out-of-range selection\n' >&2

done

# loop through the chosen groups and create advanced searches
for selected_id in ${selected_ids}; do
  checkToken
  case ${theGroupType} in
    USER)
      theData=$(apiRead "JSSResource/usergroups/id/${selected_id}" xml)
      groupName=$(/bin/echo "${theData}" | /usr/bin/xmllint --xpath '//user_group/name/text()' -)
      groupCriteria=$(/bin/echo "${theData}" | /usr/bin/xmllint --xpath '//user_group/criteria' -)

      postResult=$(apiPost "JSSResource/advancedusersearches/id/0" "<advanced_user_search><name>${groupName}</name>${groupCriteria}<site><id>-1</id><name>None</name></site></advanced_user_search>")
      checkPostResult "${postResult}" "${groupName}"
      ;;

    MOBILE)
      theData=$(apiRead "JSSResource/mobiledevicegroups/id/${selected_id}" xml)
      groupName=$(/bin/echo "${theData}" | /usr/bin/xmllint --xpath '//mobile_device_group/name/text()' -)
      groupCriteria=$(/bin/echo "${theData}" | /usr/bin/xmllint --xpath '//mobile_device_group/criteria' -)

      postResult=$(apiPost "JSSResource/advancedmobiledevicesearches/id/0" "<advanced_mobile_device_search><name>${groupName}</name><view_as>Standard Web Page</view_as>${groupCriteria}<site><id>-1</id><name>NONE</name></site></advanced_mobile_device_search>")
      checkPostResult "${postResult}" "${groupName}"
      ;;

    COMPUTER)
      theData=$(apiRead "JSSResource/computergroups/id/${selected_id}" xml)
      groupName=$(/bin/echo "${theData}" | /usr/bin/xmllint --xpath '//computer_group/name/text()' -)
      groupCriteria=$(/bin/echo "${theData}" | /usr/bin/xmllint --xpath '//computer_group/criteria' -)

      postResult=$(apiPost "JSSResource/advancedcomputersearches/id/0" "<advanced_computer_search><name>${groupName}</name><view_as>Standard Web Page</view_as>${groupCriteria}<site><id>-1</id><name>None</name></site></advanced_computer_search>")
      checkPostResult "${postResult}" "${groupName}"
      ;;
  esac
done
