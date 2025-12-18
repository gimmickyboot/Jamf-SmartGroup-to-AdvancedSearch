# Jamf-SmartGroup-to-AdvancedSearch
A script to create advanced searches from existing smart groups. Works with user, mobile device and computer groups

## How to use
run as `./jamf_smartgroup_to_advsearch.sh` for help

available options are `user` `mobile` `computer`. Use only 1 at a time.

## Example
`./jamf_smartgroup_to_advsearch.sh mobile`

Follow the prompts to choose your authentication type, ie username/password or API Roles and Clients.

A list of all groups will be displayed. Make a choice by entereing the number to the left of the ")"
```
Groups are listed as "[Jamf ID] <Group name>"

1) [1] All Managed Apple TVs
2) [2] All Managed iPads
3) [3] All Managed iPhones
4) [4] All Managed iPod touches
5) [5] All Managed Vision Pros
6) [6] All Managed Watches

Enter choice(s) (space-separated, 1-6, q to quit):
```

Multiple groups can be entered, eg `1 4 6`

Press `q` and return to quit

## Privileges
The following privileges are required (at a minumum)
```
Create Advanced Computer Searches
Create Advanced Mobile Device Searches
Create Advanced User Searches
Read Smart Computer Groups
Read Smart Mobile Device Groups
Read Smart User Groups
```
