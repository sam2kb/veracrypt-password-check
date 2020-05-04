#!/bin/bash

# Allow stopping with CTRL+C
trap '
    trap - INT
    kill -s INT "$$"
' INT

TRUECRYPT=""
DIR_MOUNT=./.tmpveramount
FILE_PREP=./prepared-passwords.txt
FILE_FOUND=./found-passwords.txt
FILE_PASSWORDS=./dict.txt

while getopts ":t" opt; do
  case "${opt}" in
    t)
        TRUECRYPT="--truecrypt"
        ;;
    *)
        echo "usage: $0 [-t] [volume1] [volume-nth]" >&2
        exit 2
        ;;
  esac
done

# {} means we keep default case
MODIFIERS="{}
{NoSpaces}
{NoSpacesSentence}
{NoSpacesCapAll}
{NoSpacesLowerAll}
{Sentence}
{CapFirst}
{CapAll}
{LowerFirst}
{LowerAll}"

SUFFIXES="!
@
..."

prep_password_list() {
	declare -A list

    # for each password (including last line))
	while IFS= read -r pass || [ -n "$pass" ]; do
        # transform the password
		while IFS= read -r mod; do
			case $mod in
			"{NoSpaces}")
				modpass="${pass//[[:blank:]]/}"
				;;
			"{NoSpacesSentence}")
				modpass=${pass//[[:blank:]]/}
				modpass="${modpass^}"
				;;
			"{NoSpacesCapAll}")
				modpass=${pass//[[:blank:]]/}
				modpass="${modpass^^}"
				;;
			"{NoSpacesLowerAll}")
				modpass=${pass//[[:blank:]]/}
				modpass="${modpass,,}"
				;;
			"{Sentence}")
				modpass="${pass^}"
				;;
			"{CapFirst}")
				modpass=$(echo "$pass" | sed "s/\b\(.\)/\u\1/g")
				;;
			"{CapAll}")
				modpass="${pass^^}"
				;;
			"{LowerFirst}")
				modpass="${pass,}"
				;;
			"{LowerAll}")
				modpass="${pass,,}"
				;;
			*)
				modpass=$pass
				;;
			esac

            # append a suffix and add to array
			while IFS= read -r suffix; do
				# each key can only appear once
				list[$modpass$suffix]=1
			done < <(printf '%s\n' "$SUFFIXES")
		done < <(printf '%s\n' "$MODIFIERS")
	done < ${FILE_PASSWORDS}

	printf '%s\n' "${!list[@]}" | sort > ${FILE_PREP}
	printf '\nPrepared %d passwords' ${#list[@]}
}

find_passwords() {
	local volume=$1
	local count=0
	local tmpdir
	tmpdir=${DIR_MOUNT}/$(date +%s)

	local cmd="veracrypt --text ${TRUECRYPT} --stdin --non-interactive --pim=0 --protect-hidden=no --mount ${volume} ${tmpdir}"

	printf '\n\nVolume: %s\nWorking >> ' "$volume"

	# Unmount all volumes
	sudo veracrypt -d

	# Create target mount directory
	mkdir -p "$tmpdir"

	while IFS= read -r p; do # for each password
		echo "$p" | sudo $cmd >/dev/null 2>&1
		if [[ $? -ne 0 ]]; then
			printf '='
		else
			printf 'Volume: %s\nPassword: %s\n\n' "$volume" "$p" >> ${FILE_FOUND}
			count+=1

			# Unmount all volumes, break the outer loop
			sudo veracrypt -d
			break 2
		fi
	done <${FILE_PREP}

	printf ' | Found passwords: %d\n' $count

	# Cleanup temp dirs after some timeout
	sleep 3
	rmdir ${DIR_MOUNT}/*
	return 0
}

# Generate the password list first, skip this if you already have your own list
prep_password_list

# Loop through each volume and try to unlock them
for volume in "$@"; do
    [ ! -z "$TRUECRYPT" ] && printf "\nTrueCrypt mode is ON\n"
    [ "$volume" == "-t" ] && continue

	find_passwords "$volume"
done