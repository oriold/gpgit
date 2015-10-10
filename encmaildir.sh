#!/bin/bash
#
# GPLv2
# GPG Encrypt a Maildir using gpgit.pl, removing any S= or W= virtual flags.
# Aug 4, 2012
#
# Change log:
#     Oct 10, 2015 (Michael F. Herbst)
#               - Remove obsolete -p from mktemp
#               - Change output.
#
#     Aug 4, 2012 (Etienne Perot)
#               - Remove third argument
#               - Changed default encryption mode to PGP/MIME (gpgit default)
#               - No need to specify path to gpgit.pl (assumes it is next to this script)
#               - No full paths to binaries
#               - Harmonize indentation
#               - Rename variables to better names
#               - Don't use a temporary file to keep track of program state
#               - Remove security vulnerability during which the (encrypted) message could be read by anyone able to read /tmp for a short while
#     Sep 03, 2011
#               - Temporary file is based on file_owner to avoid issues with permission differences.
#               - Temporary file is removed after run.
#               - Optional arguments passed to 'find'.
#               - Full paths to binaries.
#               - Removed unneccessary need of 'cat', 'grep', etc.
#     Sep 04, 2011
#               - Don't remove Dovecot index/uid unless messages have been GPG encrypted.
#               - Adjust file tests to not just use -e
#               - Quote all file operations
#     Sep 05, 2011
#               - Don't arbitrarily copy files, only overwrite the file in ~/Maildir if it differs after calling gpgencmail.pl
#               - Only rebuild the index if we have modified ~/Maildir

# Original source : http://www.dslreports.com/forum/remark,26270484 (retrieved throug google's cache)
# Slightly modified by olivier.berger@it-sudparis.eu (https://github.com/olberger/gpgit/commit/2c32d4ec201e8a3f17a9f4eff83d2514f93433e3)
# Modified by Etienne Perot

gpgit="$(dirname "$0")/gpgit"

if [[ -z "$1" || -z "$2" ]]; then
	echo "Usage is ./encmaildir.sh /path/to/Maildir certificate_user@domain.com [optional arguments passed to 'find' for messages such as '-mtime 0']"
	exit 0
fi

if [ ! -d "$1" ]; then
	echo "The directory of '$1' does not exist!"
	exit 0
fi

# Does this key exist?
gpg --list-keys "$2" > /dev/null 2>&1
if [ $? -gt 0 ]; then
	echo "A GPG key for '$2' could not be found!"
	exit 0
fi

rebuild_index=0

# Cleanup leftover temporary files, if any.
find "$1" -type f -name '*.tmp_you_can_delete_me.*' -delete

# Find all files in the Maildir specified.
echo "Calling \`find \"$1\" -type f -regex '.*/\(cur\|new\)/.*' $3\`"
echo
while IFS= read -d $'\0' -r mail; do
	# Echo what we do
	echo "Processing '$mail'"

	# Create file unreadable except by ourselves
	tempmsg="$(mktemp "$mail.tmp_you_can_delete_me.XXXXXXXXXXX")"
	chmod 600 "$tempmsg" # mktemp should have created the file as 600 already

	# This is where the magic happens
	echo "    --gpgit--> '$tempmsg'"
	"$gpgit" "$2" < "$mail" >> "$tempmsg"

	# Check to see if there are differences between the existing Maildir file and what was created by gpit.pl
	diff -qa "$mail" "$tempmsg" > /dev/null 2>&1;
	if [ "$?" -gt 0 ]; then
		# Preserve timestamps, set ownership.
		chmod "$tempmsg" --reference="$mail"
		touch "$tempmsg" --reference="$mail"
		chown "$tempmsg" --reference="$mail"

		# Remove the original Maildir message
		rm "$mail"

		# Strip message sizes, retain experimental flags and status flags, and copy the file over.
		strip_size=$(echo "$mail" | sed -e 's/W=[[:digit:]]*//' -e 's/S=[[:digit:]]*//' -e 's/,,//' -e 's/,:2/:2/')
		cp -av "$tempmsg" "$strip_size" | sed "s/^/    cp -v:     /"

		# Indexes must be rebuilt, we've modified Maildir.
		rebuild_index=1
	else
		echo "    nodiff:     Not copying, no differences between original '$mail' and encrypted '$tempmsg'."
	fi

	# Remove the temporary file
	rm "$tempmsg"
done < <(find "$1" -type f -regex '.*/\(cur\|new\)/.*' $3 -print0)
echo

# Remove Dovecot index and uids for regeneration.
if [ "$rebuild_index" -eq 1 ]; then
	echo "Removing Dovecot indexes and uids"
	find "$1" -type f -regex '.*\(dovecot-\|dovecot\.\|\.uidvalidity\).*' -delete
else
	echo "No messages found needing GPG encryption, not removing Dovecot indexes and UIDs."
fi
