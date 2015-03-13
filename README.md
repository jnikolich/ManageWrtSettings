managewrt.pl
============

managewrt.pl is a simple Perl-based tool to read, write, view and compare sets (called "lists") of NVRAM settings on routers
running WRT-style firmware such as DD-WRT.  It was originally conceived as a quick way of backing up lists of settings prior
to upgrading firmware, and then restoring the settings after the upgrade has completed.

The following commands are supported:

	get		- Reads the current value(s) of a list of NVRAM settings and saves them to a data-file, which can later be written
			  back to a router or compared with the current settings of a router at that point in time.

	set		- Takes the value(s) of a list of NVRAM settings and writes them to a router's NVRAM.  Once all value(s) have been
			  written they are committed.

	view	- Reads the current value(s) of a list of NVRAM settings, and outputs them to the screen.

	compare	- Reads the current value(s) of a list of NVRAM settings, and compares them to a saved set of value(s) using
			  your choice of "diff", "git diff" or "vimdiff".

managewrt.pl can properly handle NVRAM settings that contain such characters as single-quotes, double-quotes, backticks,
backslashes and dollar-signs.

managewrt.pl operates on "lists" of settings, which are simply text files listing one or more NVRAM setting names.  Settings
can thus be grouped together however it makes sense to do so, and then operated on together all at once.  An example of this
would be a list of all settings related to SSH-based administration of the router.  Such a text file would look simliar to
the following:

```text
limit_ssh
remote_mgt_ssh
sshd_authorized_keys
sshd_enable				
sshd_forwarding
sshd_passwd_auth			
sshd_port     
sshd_wanport
```

With such a list defined, all settings related to SSH administration could be easily saved, viewed, written and compared with
single commands.  When saved, the resulting data-files are UTF8-encoded JSON files that can be edited by the text editor of
your choice if desired, before being written back to the router later.  Note that while this can be quite convenient and
time-saving in many cases, care should always be taken to edit settings correctly, as managewrt.pl will perform exactly zero
syntax / integrity checking on saved settings when writing them back to a router.  An example of such a saved data-file is
the following:

```json
{
   "limit_ssh" : "0",
   "remote_mgt_ssh" : "0",
   "sshd_authorized_keys" : "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAgEA48rmFLbAI+LHc+AM2u/MiKHYrBx4aOJa3XK22qFCHramQteOWRJQWBUvOcrZMENo7kFsbzLhxLbsBnV6PBlPcYbAkomcjMmOLgdO65zBrcCz+TyoxzoylUOKaQ3pDI2cEFjP79Mz7jNxuC6JlzEJxJTLUuknJabVNEaKryzUvwzrip40K5hwAeasqXT2w1xeLgVEDOu54nTJndNA4p8A/KVXN9V0lowK1uLXFBHds5tHp+1grGEQAI8bbz0bB9KoxOEUFyI2V+tXyRS+LPFSXBjNc3ix8BUsOuTelj91pYdB49/sS6rPAtL1iym3FOTrod9cNSUxveaWTykZY0pSVbB7PA3R9QlhsW6Hu+ZhRt591jaXc/qZ7cEYlH1waaXAMl7fatKNSR+ThAXbRHiOV0rWr+d144F/oBOTP8bOAquFX1Gy284bKMLk= root@einstein\nssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnUkH4P2H79onbQ/A9C/rdXU8f5NW6MM0ZyRk6SdCnICWWdbJ4J7C+k4OXKJ2mi470YodIuHTqadhjs+QRYwKcFzGn8RXEEwq9letJ1rw/tg9NWa/05EMdZvXhg3wG3KXJ8edGg61xM4jCLGgF9rs/3tfqQEt0XcR6xxD8Zoj6NLlJRqPkbl/hjXjbt+c/avu6b0g4HeTHtTOHE5SEqKIW+6U90497d/UeCZIQOFN84UBtpGFuZMpxGb6PNA7kucVELrrjp0cJHeBgPDHeeMf39cTSOtbVgf5yzFVT8mx5kuuyTcqbAlWQpOxJiQ== root@biblios",
   "sshd_enable" : "1",
   "sshd_forwarding" : "0",
   "sshd_passwd_auth" : "1",
   "sshd_port" : "22",
   "sshd_wanport" : "22"
}
```

For every list that has been defined, managewrt.pl will save gotten settings on a per-router basis.  I.e. if you have 3 routers
all with slightly different sshd settings, you can define the list of all sshd settings once, and run managewrt.pl against
each of your three routers to capture the individual settings for each router.  Alternatively if you'd like to quickly copy
lists of settings from one router to another, you can get a list of settings from one router with managewrt.pl, copy the data-
file to a new name corresponding to a 2nd router, and then write those settings to the 2nd (and 3rd, etc.) router with
managewrt.pl .


REQUIREMENTS
------------

managewrt.pl is implemented as a single perl script.  As such, it requires Perl (5.10.0 or higher) to be present and
functional on the system where managewrt.pl is to be run.

managewrt.pl depends on a small number of perl modules to properly operate, which may or may not already be present on your
system.  (On the author's Fedora 21 system, all modules were automatically installed with Perl when it was installed.)  At
present the required modules are:
	Getopt::Long
	JSON::PP
	Pod::Usage
	File::Temp
	IO::Handle

managewrt.pl makes use of a very small number of utilities (e.g. ping, mktemp, cat) typically included in most unix-like
operating systems such as Linux, BSD, OSX, etc.  It should work similarly on any unix-like operating system that has
Perl 5.10.0 (or later) installed along with the modules mentioned above.  It has not been tested on Windows, but will
presumably work in conjunction with something like CygWin (a large collection of GNU and open-source tools along with a
POSIX API environment).

managewrt.pl communicates with routers via SSH.  This means that: 1) the SSH server must be running on your router(s), and
2) the ssh client 'ssh' must exist on the system where managewrt.pl is installed to.  It is also highly recommended that
key-based SSH logins be configured beforehand.  While not strictly necessary, if public/private SSH keys have not been properly
installed beforehand then every invocation of managewrt.pl will cause the user to be prompted (often multiple times per command)
to enter the valid login password for the router.

When performing compare commands, managewrt.pl supports the use of (currently) 3 comparison utilties:  diff, git, and vim.
Ensure that your choice(s) of these tools are installed beforehand.
