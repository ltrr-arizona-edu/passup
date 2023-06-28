# Password Rotation Shell Script for Linux

The simple script relies on API access to the [University of Arizona's implementation](https://confluence.arizona.edu/display/SIA/Stache+Basics)
of the [STACHE](https://www.saltycloud.com/stache/) secure credential store.
It obtains the current password for a normal user account, generates a new random
password conforming to some character class constraints, updates the password, and writes
the new password back to the credential store.

