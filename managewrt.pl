#! /usr/bin/env perl
#################################################################################
#     File Name           :     managewrt.pl
#     Created By          :     jnikolic
#     Creation Date       :     2015-02-18 10:25
#     Last Modified       :     2015-03-12 12:20
#     Description         :     Manages the NVRAM settings on a router running
#                         :     a "WRT" style of firmware such as DD-WRT.
#################################################################################
# Copyright (C) 2015 James D. Nikolich
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#################################################################################


### Define some environmental characteristics
use strict;
use warnings;
use 5.10.0;

use Getopt::Long qw( GetOptions );
Getopt::Long::Configure qw( gnu_getopt );
use JSON::PP;
use Pod::Usage;
use File::Temp qw( tempfile );;
use IO::Handle;

# Global configuration parameters
#
# Defaults are specified here, and are subject to being overwritten as follows:
#	Command-line arguments	- overwrite EVERYTHING
#	Configuration file		- overwrites these defaults
#   These defaults			- overwrite nothing
my %CFG = (
	'backslash'		=> '',
	'cmd'			=> '',
	'configfile'	=> '/etc/managewrt.conf',
	'datadir'		=> './data',
	'debug'			=> '',
	'help'			=> '',
	'listdir'		=> './lists',
	'listname'		=> '',
	'comparetool'	=> 'diff',
	'router'		=> '192.168.1.1',
);


### main()
###
### Start-of-execution point for this program.  The only global code is the
### invocation of this main function (located near the end of this file just
### before the POD), and a global config hash.
###
### Args:	@_	= All arguments passed to this program.
###
### Return:	true	= Completed OK.
###
### Exits:	TBD
###
sub main
{
	SetupConfig( \%CFG );

DebugSay( <<"ENDhere" );
backslash   = $CFG{ 'backslash' }
cmd         = $CFG{ 'cmd' }
configfile  = $CFG{ 'configfile' }
datadir     = $CFG{ 'datadir' }
debug       = $CFG{ 'debug' }
help        = $CFG{ 'help' }
listdir     = $CFG{ 'listdir' }
listname    = $CFG{ 'listname' }
comparetool = $CFG{ 'comparetool' }
router      = $CFG{ 'router' }
ENDhere

	# Terminate if specified router is not reachable for any reason.
	die "Router \'$CFG{'router'}\' down or unreachable."
		unless IsDeviceReachable( $CFG{'router'} );

	if( $CFG{'cmd'} eq "view" )
	{
		my %routerlist = ();
		LoadList( $CFG{'listname'}, $CFG{'listdir'}, \%routerlist );
		PullSettingsFromRouter( $CFG{'router'}, \%routerlist );

		OutputSettings( *STDOUT, \%routerlist, $CFG{'backslash'} );
	}
	elsif( $CFG{'cmd'} eq "compare" )
	{
		my %routerlist = ();
		LoadList( $CFG{'listname'}, $CFG{'listdir'}, \%routerlist );
		PullSettingsFromRouter( $CFG{'router'}, \%routerlist );

		my %savedlist = ();
		ReadSettingsFromSaveFile( $CFG{'listname'},  $CFG{'router'}, $CFG{'datadir'}, \%savedlist );

		CompareSettings( \%routerlist, \%savedlist, $CFG{'comparetool'} );
	}
	elsif( $CFG{'cmd'} eq "get" )
	{
		my %routerlist = ();
		LoadList( $CFG{'listname'}, $CFG{'listdir'}, \%routerlist );
		PullSettingsFromRouter( $CFG{'router'}, \%routerlist );

		SaveSettingsToSaveFile( $CFG{'listname'}, $CFG{'router'}, $CFG{'datadir'}, \%routerlist );
	}
	elsif( $CFG{'cmd'} eq "set" )
	{
		my %savedlist = ();
		ReadSettingsFromSaveFile( $CFG{'listname'}, $CFG{'router'}, $CFG{'datadir'}, \%savedlist );

		PushSettingsToRouter( $CFG{'router'}, \%savedlist );
	}
	elsif( $CFG{'cmd'} eq "dumpcfg" )
	{
		print( JSON::PP->new->utf8->canonical->pretty->encode( \%CFG ) );
	}
}


### CompareSettings()
###
### Takes two hash references - one containing live router settings, and the
### other containing saved settings - and compares them using the specified
### comparison tool.
###
### Args:	$_[0]	= Hash-reference containing live router settings/values.
###			$_[1]	= Hash-reference containing saved settings/values.
###      	$_[2]	= Comparison tool.  Must be one of:
###						- diff
###						- git
###						- vim
###
### Return:	1		= Completed successfully.
###
### Exits:	none
###
sub CompareSettings
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $routerlist		= $_[0];
	my $savedlist		= $_[1];
	my $comparetool		= $_[2];

	# Create tmpfile for live router settings, output the (sorted) settings to
	# the tmpfile, and flush output.
	my( $fh_routerlist, $fn_routerlist ) = tempfile( 'routerlist_XXXXXX', TMPDIR => 1, CLEANUP => 1 );
	OutputSettings( $fh_routerlist, $routerlist, 0 );

	# Create tmpfile for saved settings, output the (sorted) settings to the
	# tmpfile, and flush output.
	my( $fh_savedlist, $fn_savedlist ) = tempfile( 'savedlist_XXXXXX', TMPDIR => 1, CLEANUP => 1);
	OutputSettings( $fh_savedlist, $savedlist, 0 );

	# Set up the appropriate diff tool, and run it.
	my $comparecmd;
	if( $comparetool eq "diff" )	{ $comparecmd = "/usr/bin/diff    -s -u $fn_routerlist $fn_savedlist"; }
	if( $comparetool eq "git" )		{ $comparecmd = "/usr/bin/git     diff  $fn_routerlist $fn_savedlist"; }
	if( $comparetool eq "vim" )		{ $comparecmd = "/usr/bin/vimdiff -R    $fn_routerlist $fn_savedlist"; }
	system( $comparecmd );

	return 1;
}


### DebugSay()
###
### Outputs all passed parameters to stderr if debugging-output is active via
### the $CFG{'debug'} configuration setting.
###
### Args:	@_	= All parameters are to be output to stderr.
###
### Return:	1	= Completed OK.
###
### Exits:	none
###
sub DebugSay
{
	say STDERR @_ if $CFG{'debug'};
	return 1;
}


### ExecuteShellCmd()
###
### Execute the provided command string via a system() call, putting any
### resulting output (both stdout and stderr) into the output string provided
### by-reference.  The result-code of the system() call is returned via
### reference to the caller.
###
### Args:	$_[0]	= Command string to be executed via system(0 call.
###			$_[2]	= Reference to string that will contain any output.
###			$_[3]	= Reference to scalar that will contain the result-code
###                   of the command's execution..
###
### Return:	1		= Command executed successfully.
###			0		= Error during execution (check result code)
###
### Exits:	none
###
sub ExecuteShellCmd
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $command 	= $_[0];
	my $output		= $_[1];
	my $resultcode	= $_[2];

	DebugSay( "Executing [$command]" );
	( $$output = qx{$command 2>&1}, $$resultcode = $? >> 8 );
	DebugSay( "Output: [$$output]" ) unless ! defined $$output;
	DebugSay( "Status: [$$resultcode]" );

	if( $$resultcode eq 0)	{ return 1; }
	else					{ return 0; }
}


### IsDeviceReachable()
###
### Checks if the specified device is reachable and up (via ping).
###
### Args:	$_[0]	= Name of device to try reaching.
###
### Return:	1		= Device reachable and up.
###			0		= Device down, not reachable, or unresolvable.
###
###
### Exits:	none
###
sub IsDeviceReachable
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $router	= $_[0];
	my $pingbin	= '/usr/bin/ping';

	my $pingcmd = "$pingbin -c 1 $router >/dev/null 2>&1";
	DebugSay( "ping cmd: [$pingcmd]" );
	my $retval = system( $pingcmd );
	DebugSay( "system() result: [$retval]" );
	if( $retval != 0 )
	{
		$retval = $retval >>8;
		DebugSay( "Ping failed with code $retval" );
		return 0;
	}
	return 1;
}


### LoadList()
###
### Parses a config file for a list of setting names, and the populate the
### given hash-reference to contain keys corresponding to each setting.  The
### value associated with each key will be set to undefined.  The hash should
### be empty when calling this subroutine.
###
### Args:	$_[0]	= Name of the list of settings
###			$_[1]	= Directory containing list config files
### 		$_[2]	= Reference to an empty hash of settings.
###
### Return:	1		= Setting names loaded successfully.
###
### Exits:	none
###
sub LoadList
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $listname	= $_[0];
	my $listdir		= $_[1];
	my $settinglist	= $_[2];

	my $listfilename = "$listdir/$listname";

	open( LISTFILE, $listfilename )
		or die "Error opening list file \'$listfilename\' $!";
	my @lines = <LISTFILE>;
	close( LISTFILE );

	foreach( @lines )
	{
		chomp;				# Remove any trailing record-separator (e.g. CR)
		s/^\s+|\s+$//g;		# Remove any leading/trailing whitespace
		$settinglist->{$_} = undef;
	}
	return 1;
}


### MakeTmpfileRemote()
###
### Given the name/IP of a remote device, creates a tempfile on that device and
### returns the path/filename of that tempfile.
###
### Since 'mktemp' appears to be rarely (if ever) present on current dd-wrt
### builds, the local system's mktemp is used in dry-run mode to create a
### filename.  That filename is then created on the remote device.
###
### Args:	$_[0]	= Name/IP of remote device
###
### Return:	0		= Failure
###			non-0	= Name of temp file created on remote device
###
sub MakeTmpfileRemote
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $router		= $_[0];

	my $template	= "managewrt_\$(date '+%Y%m%d%H%M%S').XXXXX";
	my $tempname;
	my $cmdbuffer;
	my $cmdoutput;
	my $resultcode;

	$cmdbuffer = "mktemp --dry-run --tmpdir=/tmp $template";
	if( ! ExecuteShellCmd( $cmdbuffer, \$tempname, \$resultcode ) )
	{
		warn "Error running local 'mktemp'\nresult $resultcode";
		return 0;
	}
	chomp $tempname;

	$cmdbuffer = "ssh root\@$router -q \'>$tempname'";
	if( ! ExecuteShellCmd( $cmdbuffer, \$cmdoutput, \$resultcode ) )
	{
		warn "Error creating tmpfile '$tempname' on router '$router'\nresult $resultcode";
		return 0;
	}

	return $tempname;
}


### OutputSettings()
###
### Takes a hash reference containing nvram setting names/values, and outputs
### the contents to the specified file-handle.  The output is sorted by key
### (i.e. setting name).  Any double-quote " characters found in the values can
### optionally be preceded by a backslash.  Output is flushed afterward.
###
### Args:	$_[0]	= File handle to output to.
### 		$_[1]	= Hash reference containing settings/values to be outputted
###			$_[2]	= Should double-quotes in setting values be backslashed
###					  ( 0 = no, 1 = yes ).
###
### Return:	1		= Completed successfully.
###
### Exits:	none
###
sub OutputSettings
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $filehandle		= $_[0];
	my $settinglist		= $_[1];
	my $backslashquotes	= $_[2];

	foreach my $settingname ( sort( keys %{ $settinglist } ) )
	{
		my $settingvalue = $settinglist->{$settingname};
		if( defined $settingvalue)	# if some sort of setting value was present
		{
			PrependLiterals( \$settingvalue ) if $backslashquotes;
			print( $filehandle "$settingname\=\"$settingvalue\"\n" );
		}
		else						# If the setting value was null/not-present
		{
			print( $filehandle "$settingname\=\n" );
		}
	}
	$filehandle->flush();

	return 1;
}


### PrependLiterals()
###
### Given a reference to a string, prepends every instance of certain literal
### characters with a backslash \ character.  The referenced string itself will
### be updated to reflect processing.  The characters that will be
### prepended are:
###     			\  (backslash)
###     			"  (double quote)
###     			$  (dollar-sign)
###     			`  (backtick)
### 	
### Args:	$_[0]]	= Reference to the string to be processed.
###
### Return:	Value of the processed reference
###
### Exits:	none
###
sub PrependLiterals
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $stringref = $_[0];

	$$stringref =~ s/\\/\\\\/g;	# Treat \ characters as literals - MUST BE 1ST
	$$stringref =~ s/\"/\\\"/g;	# Treat " characters as literals
	$$stringref =~ s/\$/\\\$/g;	# Treat $ characters as literals
	$$stringref =~ s/\`/\\\`/g;	# Treat ` characters as literals

	return "$$stringref"
}


### PullSettingsFromRouter()
###
### Given a hash-reference of settings and the name/IP of a router, pulls the
### current values of the router's settings and loads them into the hash.  Any
### preexisting values will be overwritten.  The device is presumed to already
### have been tested for reachability.
###
### Args:	$_[0]	= Name of device to try reaching.
###			$_[1]	= Reference to hash of settings (keys are setting names,
###					  values will be setting values).
###
### Return:	1		= Settings pulled successfully.
###
### Exits:	Dies if an error occurs during ssh to router
###
sub PullSettingsFromRouter
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $router		= $_[0];
	my $settinglist	= $_[1];

	foreach my $settingname ( keys $settinglist )
	{
		# Build command and execute it, capturing output and result-code.
		# bail out of the subroutine if error encountered.
		my $sshcmd = "ssh -l root -q $CFG{'router'} nvram get $settingname";
		my ( $settingvalue, $resultcode );
		ExecuteShellCmd( $sshcmd, \$settingvalue, \$resultcode )
			or die "Error when running ssh on router $CFG{'router'} (result=$resultcode) $!";

		# Remove any trailing record-separators (newline chars by default), and
		# then save the value in the hash.
		chomp $settingvalue;
		$settinglist->{$settingname} = $settingvalue;
		DebugSay( $settingname, " = ", $settinglist->{$settingname} );
	}
	return 1;
}


### PushSettingsToRouter()
###
### Given a hash-reference of settings and the name/IP of a router, reads the
### most recently saved settings from a savefile and pushes them to the router.
### After all settings have been pushed, they are committed to nvram together.
### The device is presumed to already have been tested for reachability.
###
### *NOTE* The dropbear implementation of SSH on (at least) dd-wrt appears to
###        have a limit on how long a command can be, of around 900 bytes.
###        This prevents doing 'nvram set' type commands directly over SSH,
###        since some nvram settings (e.g. rc_* startup scripts) may greatly
###        exceed this limit.  To work around it, a temporary script containing
###        all the 'nvram set' and 'nvram commit' commands is pushed to the
###        /tmp directory on the router, executed, and then cleaned up.
###
### Args:	$_[0]	= Name of device to try reaching.
###			$_[1]	= Reference to hash of settings (keys are setting names,
###					  values will be setting values).
###
### Return:	1		= Settings pushed successfully.
###
###
### Exits:	Dies if an error occurs during ssh to router
###
sub PushSettingsToRouter
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $router		= $_[0];
	my $settinglist	= $_[1];

	my $cmdbuffer = "#!/bin/sh\n";
	my $cmdoutput;
	my $resultcode;
	my $sshcmd;

	my $tmpfilename = MakeTmpfileRemote( $router );
	exit 255 unless $tmpfilename;

	# Build a command-buffer containing an 'nvram set' command for each of the
	# settings in the list.  Put an 'nvram commit' at the end.
	foreach my $settingname ( keys $settinglist )
	{
		my $settingvalue = $settinglist->{$settingname};
		$settingvalue = PrependLiterals( \$settingvalue );

		# Some extra backslash'ing is required for this special case because
		# the constructed command needs to survive command-substitution several
		# times, on the system running this script and on the router itself.
		for( my $count = 1; $count <= 2; $count++ )
		{
			$settingvalue =~ s/\$/\\\$/g; # Prepend dollarsign $ characters with backslash \
			$settingvalue =~ s/\`/\\\`/g; # Prepend backtick   ` characters with backslash \
		}

		$cmdbuffer .= "nvram set $settingname=\"$settingvalue\"\n";
	}
	$cmdbuffer .= "nvram commit";

	# Push the command-buffer to the target router as a temp-file that will be
	# subsequently executed as a shell script.
	$sshcmd = "cat <<-ENDcat | ssh root\@$router -q \'cat >$tmpfilename\'\n$cmdbuffer\nENDcat\n";
	ExecuteShellCmd( $sshcmd, \$cmdoutput, \$resultcode )
		or die "Error when running pushing script to router $CFG{'router'} (result=$resultcode) $!";

	# Execute the temp-file shell script on the remote router
	$sshcmd = "ssh root\@$router -q \'sh $tmpfilename\'";
	ExecuteShellCmd( $sshcmd, \$cmdoutput, \$resultcode )
		or die "Error when executing script on router $CFG{'router'} (result=$resultcode) $!";

	return 1;
}


### ReadSettingsFromSaveFile()
###
### Reads a save-file containing a set of nvram setting names/values, and loads
### everything into the referenced hash.
###
### Args:   $_[0]   = Name of the list of settings/values to be read.
###			$_[1]	= Name / IP of router.
###         $_[2]   = Data directory in which to access save-file.
###         $_[3]   = Hash-reference in-which to store the settings/values.
###
### Return: 1       = Setting names read successfully.
###
### Exits:  none
###
sub ReadSettingsFromSaveFile
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $listname		= $_[0];
	my $router			= $_[1];
	my $datadir			= $_[2];
	my $settinglist		= $_[3];

	my $savefilename	= "$datadir/$router" . "__" . "$listname";

	# Grab the json-encoded setting names/values from the savefile
	my $json_data= do {
		open( my $LISTFILE, '<:encoding(UTF-8)', $savefilename )
			or die "Could not open savefile '$savefilename' $!";
		local $/;
		<$LISTFILE>
	};

	# Decode the data into a temporary hash, and then copy out each
	# setting name/value into the real hash-reference one-by-one.
	my $tmphash_decoded = JSON::PP->new->decode( $json_data );
	while ( my ( $key, $value ) = each ( $tmphash_decoded ) )
	{
		DebugSay( "Copying \$tmphash_decoded\{\'$key\'\} into \$settinglist\{\'$key\'\} - value [$value]" );
		$settinglist->{$key} = $value;
	}

	return 1;
}


### SaveSettingsToSaveFile()
###
### Takes a hash of nvram setting names/values and writes it to a save-file.
### The permissions on the resulting savefile are set to 0600 ( -rw------ )
### to help secure any sensitive settings.
###
### Args:	$_[0]	= Name of the list of settings/values to be saved.
###			$_[1]	= Name of router.
###			$_[1]	= Data directory in which to store save-file.
###      	$_[2]	= Hash-reference containing settings/values to be saved.
###
### Return:	1		= Setting names saved successfully.
###
### Exits:	none
###
sub SaveSettingsToSaveFile
{
	DebugSay( "Entered " . (caller(0))[3] . " [ @_ ]" );

	my $listname		= $_[0];
	my $router			= $_[1];
	my $datadir			= $_[2];
	my $settinglist		= $_[3];

	my $savefilename	= "$datadir/$router" . "__" . "$listname";

	open( my $LISTFILE, '>:encoding(UTF-8)', $savefilename )
		or die "Could not open savefile '$savefilename' $!";
	print( $LISTFILE JSON::PP->new->utf8->canonical->pretty->encode( $settinglist ) );
	close( $LISTFILE );
	my $mode = 0600; chmod( 0600, $savefilename );
	return 1;
}


### SetupConfig()
###
### Sets up the configuration that will control execution of this program.
### A reference to a config hash should be provided as the only argument, and
### may contain any defaults that are desired.  All command-line parameters are
### parsed, and integrated into the config hash overriding defaults if any
### exist.
###
### The first command-line parameter must be the 'cmd' to execute, i.e. one of:
### 	compare  view  get  set
###
### The remaining command-line parameters are processed as regular short or
### long options.
###
### Args:	$_[0]	= Reference to configuration hash, possibly containing any
###					  default values that may be desired.
###
### Return:	1		= Completed OK.
###
### Exits:	Will terminate processing with pod2usage() on any error parsing
###         the command-line parameters.
###
sub SetupConfig
{
	# Reference to global Config hash - will be populated/overwritten by values
	# obtained from the config file and command-line.
	my $REALCFG = $_[0];

	# Temporary config hash - used to stage values obtained from the config
	# file and/or command-line before being copied into the global config hash.
	my %TMPCFG;

	# First argument must the the command to be performed.  If recognized then
	# save it to the temporary config hash.  Otherwise its absence will be
	# handled momentarily.
	if( @ARGV )
	{
		my $cmd = $ARGV[0];
		if( $cmd eq "compare"
		||	$cmd eq "get"
		||	$cmd eq "dumpcfg"
		||	$cmd eq "set"
		||	$cmd eq "view" )
		{
			$TMPCFG{'cmd'} = $cmd;
			shift @ARGV;
		}
		else
		{
			$TMPCFG{'cmd'} = "invalid";
			shift @ARGV;
		}

	}

	# Read command-line options into temporary config hash.
	GetOptions(
		'backslash|b'		=> \$TMPCFG{ 'backslash' },
		'config|c=s'		=> \$TMPCFG{ 'configfile' },
		'debug|d'			=> \$TMPCFG{ 'debug' },
		'help|h'			=> \$TMPCFG{ 'help' },
		'list|l=s'			=> \$TMPCFG{ 'listname' },
		'outputcompare|o=s'	=> \$TMPCFG{ 'comparetool' },
		'router|r=s'		=> \$TMPCFG{ 'router' },
	) or pod2usage( "$0: Error processing options.\n" );

	# Exit with help if requested
	pod2usage( -verbose => 3 ) if $TMPCFG{'help'};

	# If config-file specified on cmd-line, then use it. Otherwise if a default
	# config-file is specified, then use it.  Only use each setting from a
	# config-file when no corresponding setting was provided on the cmd-line.
	my $cfgfilename;
	if( defined $TMPCFG{'configfile'} )			{ $cfgfilename = $TMPCFG{'configfile'};	   }
	elsif( defined  $REALCFG->{'configfile'} and -f $REALCFG->{'configfile'} )	{ $cfgfilename = $REALCFG->{'configfile'}; }
	if( defined $cfgfilename )
	{
		my $json_data = do{
			open( my $CFGFILE, '<:encoding(UTF-8)', $cfgfilename )
				or die "could not open config-file '$cfgfilename' $!";
			local $/;
			<$CFGFILE>
		};
		my $tmphash_decoded = JSON::PP->new->decode( $json_data );
		while( my( $key, $value ) = each( $tmphash_decoded ) )
		{
			next if defined $TMPCFG{$key};	# skip if cmd-line equivalent provided
			next if $key eq 'help';			# skip if setting requests help
			next if $key eq 'configfile';	# skip if setting redundantly specifies a config file
			$TMPCFG{$key} = $value;
		}
	}

	# Exit if command or any mandatory arguments were omitted
	pod2usage( "$0: Must specify a valid command as 1st option.\n" ) unless defined $TMPCFG{'cmd'};
	pod2usage( "$0: Must specify a valid command as 1st option.\n" ) if( $TMPCFG{'cmd'} eq "invalid" );
	pod2usage( "$0: Must specify a listname.\n" )          			 unless defined $TMPCFG{'listname'};
	pod2usage( "$0: Must specify a router.\n" )            			 unless defined $TMPCFG{'router'};

	# Copy any options from temporary config hash in to global config hash.
	# Skip over any zero-length options - for some reason GetOptions() appears
	# to auto-vivify all potential options whether or not they are actually
	# encountered on the command-line.
	while ( my ( $key, $value ) = each ( %TMPCFG ) )
	{
		length $value or next;
		DebugSay( "Copying \$TMPCFG\{\'$key\'\} into \$REALCFG\{\'$key\'\} - value [$value]" );
		$REALCFG->{$key} = $value;
	}

	# Exit if unrecognized compare method specified
	pod2usage( "$0: Unrecognized compare output method '$REALCFG->{'comparetool'}'." )
		unless ( $REALCFG->{'comparetool'} eq "diff"
		||	 	 $REALCFG->{'comparetool'} eq "git"
		||	 	 $REALCFG->{'comparetool'} eq "vim" );

	return 1;
}


main( @ARGV );

__END__

=head1 NAME

    managewrt.pl - Manage nvram settings on a "WRT" style router.

=head1 SYNOPSIS

    managewrt.pl <CMD> -r <router> -l <listname> [option...]

		where <CMD> is one of:  compare, view, get, set, dumpcfg

    managewrt.pl --help or -h for help

=head1 DESCRIPTION

    Manage the nvram settings on a router running a "WRT" style of firmware such
    as DD-WRT.  Settings are grouped together into lists and operated on
    together.  Lists are configured via drop-in list files.

    This script utilizes SSH to interact with the router.  It is recommended
    that SSH public keys be set up between the system running this script and
    the router beforehand, otherwise use of the script will likely result in
    password prompts being constantly displayed.

    If a configuration file is specified, or if the default configuration file
    /etc/managewrt.conf is present, then settings will be taken from there.
    These settings override default settings, but are themselves overriden by
    anything specified on the command-line.

=head1 OPTIONS

=head2 Command

    The first argument must be one of the following commands to perform:

        compare  Retrieve a list of settings from the router and compare them
                 with the last recorded values.

        view     Retrieve a list of settings from the router and display them
                 to standard-output.

        get      Retrieve a list of settings from the router and save them to
                 a local savefile.

        set      Load a list of settings from the most recent savefile for that
                 list and write/commit them to the router.

        dumpcfg  Performs no operations on the router.  Instead, displays the
				 current configuration (including any default parameters and
				 command-line arguments).  The output is in a format that can
				 be redirected to a file and subsequently used as a config-file
				 with the --config <filename> option.

=head2 Mandatory Arguments

    --router=<router>  or  -r <router>
        Specify the router to operate on. <router> may be either an IP address
        or a resolvable hostname.

    --list=<listname>  or -l <listname>
        Specify the name of the list of settings to operate on.  <listname> must
        correspond to a drop-in configuration file that has been set up.

=head2 Optional Arguments

    --backslash  or  -b
        Prepend a backslash \ character to certain literals, to help prevent
        them from being expanded (e.g. if piped into subsequent commands,
        etc.).  The following literals will be prepended by a backslash:
            \  (backslash)
            "  (double quote)
            $  (dollar-sign)
            `  (backtick)

    --config=<filename>  or  -c <filename>
        Specifies a configuration file to load options from (overrides defaults
        but is overwritten by explicit command-line options).

    --debug  or  -x
        Enable debugging output to standard-error.

    --outputcompare=<diff|vim|git>  or -o <diff|vim|git>
        Specify the output method when performing a 'compare' operation.
        'diff'    - Use external 'diff' command to produce comparison output.
        'vim'     - Use vim in 'vimdiff' mode to produce comparison output.
        'git'     - Use 'git diff' to produce (possibly colorized) output.

    --help  or  -h
        Displays the help page for this script.

=head1 WARNINGS

    Note that no attempt is made to obscure/filter out any sensitive settings
    such as passwords.  Care should be taken when handling such settings.  This
    script will do the following in an attempt to reduce risk:

        1. When getting current settings from a router and saving them to a
           save-file, the file's permissions will be set to 0600 ( -rw------- )
           to prevent access by any user other than the owner and root.

           (NOT YET IMPLEMENTED)
        2. When accessing a list config-file or a setting save-file, execution
           will terminate if the file has any non-owner permissions enabled, in
           an attempt to minimize the risk of tampering.

=cut
