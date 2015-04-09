#adventure.pl
#by Bill Hallahan and Joe DiSabito
#Loads in and allows the user to play a text based adventure game
# referred to http://perldoc.perl.org/
#http://stackoverflow.com/questions/953707/in-perl-how-can-i-read-an-entire-file-into-a-string
#http://www.regular-expressions.info/lookaround.html
#http://stackoverflow.com/questions/11776184/how-to-store-hash-of-hashes-in-moose
#http://www.comp.leeds.ac.uk/Perl/matching.html
#http://stackoverflow.com/questions/7071229/printing-perl-hash-keys
#http://www.perlmonks.org/?node_id=620338
#http://stackoverflow.com/questions/9444915/how-to-check-if-a-hash-is-empty-in-perl

use strict;
use warnings;
use Text::Wrap;
use List::Util;
use POSIX ();

#defines a Moose class that reads in information from files
{
	package ReadFromFile;
	use Moose;
	
	#process a line that sets a property to a single value
	#arguments:
	#	$_[0] = the line to check
	#	$_[1] = the property to check
	#	$_[2] = the character that should come after the equals sign, before the property value
	#	$_[3] = the character that should come after the property value
	#returns: the property value if the line is valid, 0 otherwise
	sub processBoundedProperty {
		my ($self, $line, $propertyName, $charAfterEquals, $charAtEnd) = @_;
		
		#checks a line begins with the property name, followed by a equal sign, the beginning char(excusing spaces), with ending char at end
		return $1 if ($line =~ /^$propertyName\s*={1}\s*$charAfterEquals{1}(.*)$charAtEnd{1}\s*$/s);
		return 0;
	}

	#process a property being set to a boolean value
	#arguments:
	#	$_[0] = the line to check
	#	$_[1] = the property to check
	#returns: 0 if the property is not being set, 1 if it is being set to false, and 2 if it is being set to true
	sub processBoolProperty {
		my ($self, $line, $propertyName) = @_;
		#checks if a line begins with the given property name, followed by one equal sign
		if ($line =~ s/^$propertyName\s*=\s*(.*)//)
		{
			warn "Bool property $propertyName given invalid value $1, set to false by default.\n" if ($1 ne "true" && $1 ne "false");
			return ($1 eq "true") ? 2 : 1;
		}
		
		return 0;
	}

	#process a property being set to a string value
	#arguments:
	#	$_[0] = the line to check
	#	$_[1] = the property to check
	#returns: the property value if the line is valid, 0 otherwise
	sub processStringProperty {
		my $self = shift;
	
		return processBoundedProperty($self, $_[0], $_[1], '"', '"');
	}
	
	#process several properties being set to a string values, with variables given to set
	#arguments:
	#	$_[0] = the line to check
	#	$_[n] = the variable to set (n odd)
	#	$_[n+1] = the property to check
	#post: if n+1 is the property being set, n is set to it; all other properties stay the same.
	#returns: positive number if the line sets one of the properties; 0 otherwise
	sub processStringPropertiesVars {
		my $self = shift;
		my $argNum = @_;
	
		my $i = 1;
		
		while ($i < $argNum)
		{
			if (my $val = processStringProperty($self, $_[0], $_[$i + 1]))
			{
				$_[$i] = $val;
				return 1;
			}
			$i += 2;
		}
		
		return 0;
	}
	
	#process several properties being set to a string values, with subfunctions given to set
	#arguments:
	#	$_[0] = the line to check
	#	$_[n] = the function to use to set (n odd)
	#	$_[n+1] = the property to check
	#post: if n+1 is the property being set, n is set to it; all other properties stay the same.
	#returns: positive number if the line sets one of the properties; 0 otherwise
	sub processStringPropertiesSubs {
		my $self = shift;
		my $argNum = @_;
	
		my $i = 1;
		
		while ($i < $argNum)
		{
			if (my $val = processStringProperty($self, $_[0], $_[$i + 1]))
			{
				$_[$i]($val);
				return 1;
			}
			$i += 2;
		}
		
		return 0;
	}
	
	#takes in a list of property values and processes the first valuse
	#arguments:
	#	$_[0] = the line to check
	#	$_[1] = the property to check
	#	$_[2] = the character that the values start should be indicate by (optional- if missing, assumed to be a quote)
	#	$_[3] = the character that the values end should be indicate by (optional- if missing, assumed to be a quote)
	#returns: a list containing, in order:
	#	0 - the list with the first property removed as a string
	#	1 - the value of the first attribute
	#	2 - the character (either , or :) that comes immediately after the value
	sub getPropertyAndEnd {
		my $length = @_;
		my $self = shift;
		my $val = shift;
		my $beginChar = '"';
		my $endChar = '"';
		
		if ($length > 2) {
			$beginChar = shift;
		}
		
		if ($length > 3) {
			$endChar = shift;
		}
		
		my $attrib = "", my $end = "";
	
		if ($val =~ s/^\s*$beginChar(.*?)$endChar\s*([,:])//)
		{
			$attrib = $1;
			$end = $2;
		}
		elsif ($val =~ s/^\s*$beginChar(.*)$endChar//)
		{
			$attrib = $1;
			$end = "";
		}
		
		return ($val, $attrib, $end);
	}
	
	#takes in a list of property values and processes the first value, which may be a single value or another list
	#arguments:
	#	$_[0] = the line to check
	#	$_[1] = the property to check
	#returns: a list containing, in order:
	#	0 - the list with the first property/list of properties removed
	#	1...n - the value of the first attribute, or the n attributes in the list in the first position
	#	n + 1 - the character (either , or :) that comes immediately after the value
	sub getOptionalListPropertyAndEnd {
		my $self = shift;
		my $val = shift;
		my (@tempList, @attribList);
		my $end;

		if ($val =~ s/^\s*{(.*?)}\s*([,:}])*//)
		{
			my $subPart = $1;
			@tempList = split(":", $subPart);
			
			#remove quotes
			for my $i (@tempList)
			{
				$i =~ s/^\s*"+\s*//;
				$i =~ s/\s*"+\s*$//;
			
				@attribList = (@attribList, $i);
			}
			
			$end = $2;
		}
		elsif ($val =~ s/^\s*"(.*?)"\s*([,:}])*//)
		{
			@attribList = ($1);
			
			$end = $2;
		}
		
		for my $i (@attribList)
		{
			if ($i =~ /^\s*$/)
			{
				return ($val, $end);
			}
		}
		
		return ($val, @attribList, $end);
	}

	#arguments:
	#	$_[0] = a line from a file with properties
	#returns: the line with spaces at the beginning and end, the final semicolon, and comments removed
	#replaces "\#" with "#" (so as to allow "#" in values)
	sub removeUnneeded {
		my $self = shift;
		my $line = shift;
		
		while ($line =~ s/([^\\]#.+\n?|^#.+\n?)//){}
		while ($line =~ s/\\#/#/){}
		
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;
		$line =~ s/;$//;
		
		return $line;
	}
	
	#to be used at the end of attempts to catch properties, as the last few patterns possible to match
	#arguments:
	#	$_[0] = the file the line is from
	#	$_[1] = the line in question
	#returns: the line is ignored, or an error is thrown
	sub processUncaughtLine{
		my $self = shift;
		my $file = shift;
		my $line = shift;
		
		if ($line eq "") { }
		else
		{
			die "Error in file: $file at line:\n$line\n";
		}
	}
	
	no Moose;
	__PACKAGE__->meta->make_immutable;
}


#declares item object
{
	package Item;
	use Moose;
	
	extends 'ReadFromFile';
	
	#defines attributes for instances of Item
	has 'fileName' => (is => 'rw', 'isa'=>'Str');
	has 'name' => (is => 'rw', isa => 'Str');
	has 'lookDescription' => (is => 'rw', isa => 'Str');
	has 'heldDescription' => (is => 'rw', isa => 'Str');
	has 'canTake' => (is => 'rw', isa => 'Bool');
	has 'decorative' => (is => 'rw', isa => 'Bool');
	has 'droppable' => (is => 'rw', isa => 'Bool', default => 1);
	has 'uniqueCommands' => (traits => ['Hash'],
							 is => 'rw',
							 isa => 'HashRef[HashRef]',
							handles => {
								commandExists => 'exists',
								setUniqueCommand => 'set',
								getUniqueCommand => 'get',
								noCommands => 'is_empty', } );
	
	#BUILD called by Moose automatically after new
	sub BUILD {
		my $self = shift;
		my $fileName = $self->fileName;
		
		$self->readItem("${main::fileDir}$fileName");
	}
	
	#IMPORTANT: This function should only be called in build
	#pre: the item has not been initialized (this function has not been called
	#post: the items has had it's values initialized
	sub readItem {
		my $self = shift;
		
		my $file = $_[0];
		
		open(my $fh, "<", $file)
			or die("The file $file does not exist, so you cannot load a item from it.\n");
			
		local $/ = ";";
			
		my @slurp = <$fh>;
		
		for my $line (@slurp)#go through each line
		{
			$line = $self->removeUnneeded($line);
		
			my $val;

			if ($self->processStringPropertiesSubs($line,
												   sub { $self->name( $_[0]); }, "itemName",
												   sub { $self->lookDescription($_[0]); }, "lookDescription",
												   sub { $self->heldDescription($_[0]); }, "heldDescription")
												   ) {}
			elsif ($val = $self->processBoolProperty($line, "canTake", "", ""))
			{
				$self->canTake($val - 1);
			}
			elsif ($val = $self->processBoolProperty($line, "decorative", "", ""))
			{
				$self->decorative($val - 1);
			}
			elsif ($val = $self->processBoolProperty($line, "droppable", "", ""))
			{
				$self->droppable($val - 1);
			}
			#reads in unique commands from file
			elsif ($val = $self->processBoundedProperty($line, "uniqueCommands", "{", "}"))
			{
				my $end;
				#goes through each command
				do {
					my (@effectItemsList, %middleWordHash);
					
					#hashRef to store all information about command
					my $cmdHashRef = { "Description" => "",
									   "Location1" => "",
									   "Location2" => "",
									   "Effect" => "",
									   "EffectItems" => \@effectItemsList,
									   "Item1" => "",
									   "MiddleWord" => \%middleWordHash,
									   "Item2" => ""};
				
					#read in and store names of command
					my @nameList;
					($val, @nameList) = $self->getOptionalListPropertyAndEnd($val);
					$end = pop @nameList;
					
					for my $i (@nameList)
					{
						$self->setUniqueCommand(lc $i, $cmdHashRef);
					}
					
					#reads in description of command and locations of involved items of command
					($val, $cmdHashRef->{"Description"}, $end) = $self->getPropertyAndEnd($val);					
					($val, $cmdHashRef->{"Location1"}, $end) = $self->getPropertyAndEnd($val);					
					($val, $cmdHashRef->{"Location2"}, $end) = $self->getPropertyAndEnd($val);

					#reads in effect of command
					my $effect;
					($val, $effect, $end) = $self->getPropertyAndEnd($val);
					$cmdHashRef->{"Effect"} = $effect;
					
					if ($effect ne "NO_EFFECT")
					{		
						my @itemList;
						#reads in and stores list of items to be brought in by command
						($val, @itemList) = $self->getOptionalListPropertyAndEnd($val);
						$end = pop @itemList;
						
						@effectItemsList = map({Item->new(fileName => $_)} @itemList);
					}

					if ($end eq ",")
					{
						#reads in and stores item1, the first item of the unique command
						my $item1;
						($val, $item1, $end) = $self->getPropertyAndEnd($val);
						$cmdHashRef->{"Item1"} = lc $item1;

						if ($end eq ",")
						{
							#reads in and stores list of allowable middle words of unique command
							($val, my @middleWordList) = $self->getOptionalListPropertyAndEnd($val);
							$end = pop @middleWordList;
								
							for my $i (@middleWordList)
							{
								$middleWordHash{lc $i} = lc $i;
							}
							
							#reads in and stores item2, the second item of the unique command
							my $item2;
							($val, $item2, $end) = $self->getPropertyAndEnd($val) if ($end eq ",");
							$cmdHashRef->{"Item2"} = lc $item2;
						}
					}
				} while ($end eq ":")
			}
			else
			{
				$self->processUncaughtLine($file, $line);
			}
		}
	}
	
	#arguments:
	#	$_[0] = fileName
	#returns: an item object based on that file
	sub itemFromFileName {
		return Item->new(fileName => $_[0]);
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: the description for a command
	sub getCommandDescription {
		my ($self, $cmd) = @_;

		return $self->getUniqueCommand($cmd)->{"Description"};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: the location for the first item in that command
	sub getCommandLocation1 {
		my ($self, $cmd) = @_;

		return $self->getUniqueCommand($cmd)->{"Location1"};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: the location for the second item in that command
	sub getCommandLocation2 {
		my ($self, $cmd) = @_;

		return $self->getUniqueCommand($cmd)->{"Location2"};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: the effect for a command
	sub getCommandEffect {
		my ($self, $cmd) = @_;
	
		return $self->getUniqueCommand($cmd)->{"Effect"};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: a list of effect items for a command
	sub getCommandEffectItems {
		my ($self, $cmd) = @_;

		return @{$self->getUniqueCommand($cmd)->{"EffectItems"}};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns:the first item valid for a command
	sub getCommandItem1 {
		my ($self, $cmd) = @_;

		return $self->getUniqueCommand($cmd)->{"Item1"};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: a hash of the middle words valid for a command
	sub getCommandMiddleWord {
		my ($self, $cmd) = @_;
	
		return $self->getUniqueCommand($cmd)->{"MiddleWord"};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#	$_[1] = a candidate for middle word
	#returns: a positive value if valid, 0 otherwise
	sub checkMiddleWordValid {
		my ($self, $cmd, $middle) = @_;
	
		if ($self->checkMiddleWordEmpty($cmd))
		{
			return ($middle eq "");
		}
		
		my $middleWordHash = $self->getCommandMiddleWord($cmd);
		return exists $middleWordHash->{$middle};
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: a positive value if empty, 0 otherwise
	sub checkMiddleWordEmpty {
		my ($self, $cmd) = @_;
	
		my %middleWordHash = %{$self->getCommandMiddleWord($cmd)};
		return  !%middleWordHash;
	}
	
	#arguments:
	#	$_[0] = a command in the item
	#returns: the second item valid for a command
	sub getCommandItem2 {
		my ($self, $cmd) = @_;

		return $self->getUniqueCommand($cmd)->{"Item2"};
	}
	
	no Moose;
	__PACKAGE__->meta->make_immutable;
}

#declares room object
{
	package Room;
	use Moose;
	use Item;
	
	extends 'ReadFromFile';
	
	#defines attributes for instances of Room
	has 'fileName' => (is => 'rw', 'isa'=>'Str');
	has 'name' => (is => 'rw', isa => 'Str');
	has 'description' => (is => 'rw', isa => 'Str');
	has 'itemHash' => (traits => ['Hash'],
					   is => 'rw',
					   isa => 'HashRef[Item]',
					   handles => {
							itemExists => 'exists',
							setItem => 'set',
							getItem => 'get',
							deleteItem => 'delete',
							noItems => 'is_empty', } );
	has 'exitHash' => (traits => ['Hash'],
					   is => 'rw',
					   isa => 'HashRef[HashRef]',
					   handles => {exitRefExists => 'exists',
						           setExitRef => 'set',
								   getExitRef => 'get',
								   noExitRefs => 'is_empty', } );
	has 'tagArray' => (traits => ['Array'],
					   is => 'rw',
					   isa=> 'ArrayRef[HashRef]',
					   predicate=>'hasTagArray',
					   handles => {allTags => 'elements',
								   addTag => 'push', } );
	
	{
		our $existingRooms;
		
		#pre: the room in the file given has not been initialized (this function has not been called before With the given filename)
		#post: we load a room, and all rooms that connect to it
		#arguments:
		#	$_[0] = the name of a room file
		#returns: the object itself, so you can just write:
		#		my $room = (Room->new)->init("room.txt");	
		sub init {
			my $self = shift;
			$self->fileName(shift);
			$existingRooms = {} unless defined $existingRooms;
			
			$existingRooms->{$self->fileName} = $self;
			
			my $fileName = $self->fileName;
			$self->readRoom("${main::fileDir}${fileName}");

			return $self;
		}
		
		#IMPORTANT: This function should only be called in init
		#pre: the room has not been initalized (this function has not been called)
		#post: the room has had it's values initialized, and items in it are created
		sub readRoom {
			my $self = shift;
			my $file = shift;
			
			open(my $fh, "<", $file)
				or die("The file $file does not exist, so you cannot load a room from it.\n");
				
			local $/ = ";";
				
			my @slurp = <$fh>;

			for my $line (@slurp)#go through each line of the file
			{		
				#gets rid of unnecessary spaces and semicolon before reading in info
				$line = $self->removeUnneeded($line);
					
				my $val;
				
				#reads in and stores name and description of room
				if ($self->processStringPropertiesSubs($line,
													   sub { $self->name($_[0]); }, "name",
													   sub { $self->description($_[0]); }, "description")) {}
				#reads in file names of the item list of the room
				#creates items, then stores them in a hash
				elsif ($val = $self->processBoundedProperty($line, "itemList", "{", "}"))
				{			
					my $attrib;
					my $end = ":";
					
					while ($end eq ":"){
						($val, $attrib, $end) = $self->getPropertyAndEnd($val);
											
						my $item = Item->new(fileName => $attrib);
						$self->setItem(lc $item->name, $item);	
					}
				}
				#reads in list of tags
				elsif ($val = $self->processBoundedProperty($line, "tagList", "{", "}"))
				{			
					my $attrib;
					my $end = ":";
					
					#reads in information about the tags to be used to make the room description
					while ($end eq ":"){
						my $tagHashRef = { "iname" => "",
											"tag" => "",
											"possiblity1" => "" ,
											"possibility2" => "", };
						
						$self->addTag($tagHashRef);
					
						($val, $tagHashRef->{"name"}, $end) = $self->getPropertyAndEnd($val);
						($val, $tagHashRef->{"tag"}, $end) = $self->getPropertyAndEnd($val);
						($val, $tagHashRef->{"possibility1"}, $end) = $self->getPropertyAndEnd($val);
						($val, $tagHashRef->{"possibility2"}, $end) = $self->getPropertyAndEnd($val);
					}
				}
				elsif ($val = $self->processBoundedProperty($line, "exitList", "{", "}"))
				{
					my $end;
					
					#reads in each exit
					do {				
						#hash to store values of exit
						my $exitHashRef = { "exitDescr" => "",
											"fileName" => "",
											"lockedDescr" => "" ,
											"locked" => 0,
											"roomRef" => -1, };
					
						#reads in list of names
						my @nameList;
						($val, @nameList) = $self->getOptionalListPropertyAndEnd($val);
						$end = pop @nameList;
						
						for my $i (@nameList)
						{
							$self->setExitRef(lc $i, $exitHashRef);
						}
						
						#reads in exit description
						($val, $exitHashRef->{"exitDescr"}, $end) = $self->getPropertyAndEnd($val);				
						
						#reads in file name of room exit leads to
						my $fileName;
						($val, $fileName, $end) = $self->getPropertyAndEnd($val);
						$exitHashRef->{"fileName"} = $fileName;
						
						#determines whether exit is locked and gets locked description
						if ($end eq ",")
						{
							$exitHashRef->{"locked"} = 1;
							($val, $exitHashRef->{"lockedDescr"}, $end) = $self->getPropertyAndEnd($val);

							if ($end eq ","){
								my $lockedVal;
								
								($val, $lockedVal, $end) = $self->getPropertyAndEnd($val, "", "");
								$exitHashRef->{"locked"} = ($lockedVal eq "true");
								if ($lockedVal ne "true" && $lockedVal ne "false")
								{
									print "Exit in $file has locked set to $lockedVal, a value other than true or false.  Set to false by default.\n\n";
								}
							}
						}
						
						#check if the room this exit leads to has already been loaded, and load it if not
						if (exists $existingRooms->{$fileName})
						{
							$exitHashRef->{"roomRef"} = $existingRooms->{$fileName};
						}
						else
						{
							my $room = (Room->new)->init($fileName, $existingRooms);
							$existingRooms->{$fileName} = $room;
							
							$exitHashRef->{"roomRef"} = $room;
						}
						
					} while ($end eq ":");
				}
				else
				{
					$self->processUncaughtLine($file, $line);
				}
			}
		}
	}
	
	#arguments:
	#	$_[0] = a exit in the room
	#returns: the description for an exit
	sub getExitDescr {
		my ($self, $exit) = @_;
	
		return $self->getExitRef($exit)->{"exitDescr"};
	}
	
	#arguments:
	#	$_[0] = a exit in the room
	#returns: the file name for an exit
	sub getExitFileName {
		my ($self, $exit) = @_;
	
		return $self->getExitRef($exit)->{"fileName"};
	}
	
	#arguments:
	#	$_[0] = a exit in the room
	#returns: the description for an exit when it is locked
	sub getExitLockedDescr{
		my ($self, $exit) = @_;
	
		return $self->getExitRef($exit)->{"lockedDescr"};
	}
	
	#arguments:
	#	$_[0] = a exit in the room
	#returns: 0 if not locked, !0 if locked
	sub getExitLocked{
		my ($self, $exit) = @_;

		return $self->getExitRef($exit)->{"locked"};
	}
	
	#arguments:
	#	$_[0] = a exit in the room
	#	$_[1] = 0 if set to not locked, !0 if set to locked
	sub setExitLocked{
		my ($self, $exit, $locked) = @_;

		$self->getExitRef($exit)->{"locked"} = $locked;
	}
	
	#arguments:
	#	$_[0] = a exit in the room
	#returns: the room for an exit
	sub getExitRoom{
		my ($self, $exit) = @_;
	
		return $self->getExitRef($exit)->{"roomRef"};
	}
	
	#returns: the rooms description, with all tags replaced with the appropriate values
	sub filledInDescription {
		my $self = shift;
		my $otherItemsList = shift;
		
		my $printDescription = $self->description;
		my %itemHashes = %{$self->itemHash} if (not $self->noItems);
		
		#replace tags with the appropriate text
		if ($self->hasTagArray)
		{
			my @tags = $self->allTags;
	
			for my $tagInfo (@tags)
			{
				#retrieves information about tag
				my $name = $tagInfo->{"name"};
				my $tag = $tagInfo->{"tag"};
				my $replacement;
								
				#if an item with $name exists  in the current room, get the present text
				if ($self->itemExists($name)) {
					$replacement = $tagInfo->{"possibility1"};
					delete $itemHashes{$name};
				}
				#else, if an exit with $name exists get the appropriate text
				elsif ($self->exitRefExists($name)) {
					$replacement = $tagInfo->{"possibility1"};

					$replacement = $tagInfo->{"possibility2"} if ($self->getExitLocked($name));
				}
				#otherwise, fall through to  get nonpresent text
				else{
					$replacement = $tagInfo->{"possibility2"};
				}
				
				#do the actual replacing
				$printDescription =~ s/$tag/$replacement/;
			}
		}
		
		my $itemList = "";
		my $name;
		my $num = 0;
		
		#list all items in the room that are decorative and not shown by tags
		if (not $self->noItems)
		{		
			for my $key (%itemHashes)
			{
				if ($self->itemExists($key))
				{
					my $item = $self->getItem($key);
				
					if ($item->decorative) {
						if (not $itemList)
						{
							$itemList = "$otherItemsList";
						}
					
						$num += 1;
						$name = uc $item->name;
						$itemList ="$itemList a $name,";
					}
				}
			}
			
			#if needed, add "and" to the item list and add punctuation
			if ($itemList)
			{
				#remove last ","
				$itemList =~ s/,$//;
				
				#add "and" if needed
				$itemList =~ s/a $name$/and a $name/ if ($num >= 2);
				$itemList = "$itemList.";
			}
		}
	
		return "$printDescription$itemList";
	}
	
	no Moose;
	__PACKAGE__->meta->make_immutable;
}

{
	package main;

	our $fileDir = "";

	use Item;
	use Room;
	use ReadFromFile;
	
	print "----------------------------------\n";
	print "|  A Test-Based Adventure Engine |\n";
	print "| Bill Hallahan and Joe DiSabito |\n";
	print "----------------------------------\n";
	
	print "Enter name of Game folder: ";
	
	$fileDir = <>;
	
	$fileDir =~ s/\n/\//;
	
	my $gameName = "Game";
	my $startDescription = "Start of game.";
	
	my $prompt = "What do you do?";
	my $inventoryName = "Inventory:";
	my $otherItemsList = " Also, you can see";
	
	my $invalidDirError = "You can't go that way.";
	my $lockedDirError = "There is something blocking that direction.";
	my $invalidLookError = "You can't see that.";
	my $invalidTakeUnseenError = "You can't see that.";
	my $invalidTakeCantTakeError = "You can't take that.";
	my $takeNoItemSpecifiedError = "Name the object you are referring to.";
	my $invalidDropCantDropError = "You can't drop that.";
	my $invalidDropNonExistentError = "You don't have that item.";
	my $dropNoItemSpecifiedError = "Name the object you are referring to.";
	my $invalidCommandError = "Invalid Command.";
	
	my %commands;
	my %inventory;
	
	my ($startingRoom, $endingRoom, $endingDescr, $help)
	    = readStartFile("${fileDir}gameLayout.txt", \%commands);
	
	#this variable is in Text::Wrap.  It determines the number of columns of text to wrap at, respecting whitespace
	$Text::Wrap::columns = 70;
		
	print wrap("","", "Welcome to $gameName!\n");
	
	print "--------------------------------------------------\n";
	print wrap("","", "$startDescription\n");
	
	print wrap("","", "Press ENTER to begin.\n");
	
	my $nothing = <>;
	
	#starts player in starting room
	my $currentRoom = Room->new->init($startingRoom);

	my $continue = 1;
	my $descr;
	
	#prints description of starting room
	print wrap("","", $currentRoom->filledInDescription($otherItemsList));
	
	#enter game loop
	while ($continue){
		print "\n\n$prompt";
		
		my $input = <>;
		$input =~ s/\n//;
		
		#returns proper response based on command
		processInput($input);
		
		#if win condition has been achieved, game ends
		if ($currentRoom->fileName eq $endingRoom){
			print wrap("","", "\n$endingDescr");
			$continue = 0;
		}
	}
	
	#post: the user has been given feedback on an attempted action, and variables have been updated as needed
	#arguments:
	#	$_[0] = the user's input
	sub processInput {
		my $input = lc shift;
		
		$input =~ s/^\s+//;
		$input =~ s/\s+$//;
		
		my @inputList = split(" ", $input);	
		my $inputLength = @inputList;
		my $command = "";
		my $tryToMatch = 0;
		
		#given non-empty command, fills out inputList to avoid errors
		if ($inputLength == 0)
		{
			$inputList[0] = "";
			$inputLength = 1;
		}
			
		my $loop = 1;
		
		
		while ($loop == 1){
			$loop = 0;
			
			my $result = 0;
			
			#depending on type of command, different result is carried out
			if (exists($commands{$inputList[0]})){			
				$command = $commands{$inputList[0]};
				$tryToMatch = 1;
			
				if ($command eq "go"){
					$result = go(@inputList);
				}elsif($command eq "look"){
					$result = look(@inputList);
				}elsif ($command eq "get"){
					$result = get(@inputList);
				}elsif ($command eq "drop"){
					$result = drop(@inputList);
				}elsif ($command eq "inv"){
					print "$inventoryName\n";
					print "$_\n" for keys %inventory;
					$result = 1;
				}elsif ($command eq "help"){
					print wrap("","", $help);
					$result = 1;
				}elsif ($command eq "quit"){
					$continue = 0;
					$result = 1;
				}
			}
			else {
				my $checkTry;
			
				($result, $checkTry) = uniqueCommands(@inputList);
				
				#prevent errors if multiples items have similar commands
				$tryToMatch = List::Util::max $checkTry, $tryToMatch;
			}
			
			#if no output and no more strings to check
			if (!$result && $#inputList <= $tryToMatch) {
				print wrap("","", "$invalidCommandError");
				$result = 1;
			}
			
			#if more output but can check other combinations of strings
			if (!$result && $#inputList >= $tryToMatch)
			{
				#we can move over another element of inputlist
				$inputList[$tryToMatch] = "$inputList[$tryToMatch] $inputList[$tryToMatch + 1]";
				@inputList = @inputList[0..$tryToMatch,$tryToMatch + 2..$#inputList];
				$loop = 1;
			}
		}
	}
	
	#post: outputs the result of the user typing go and a direction, changing $currentRoom as needed
	#arguments:
	#	@_: the user's input, with each word in a different index
	#returns: 1 if displayed output, 0 if there should be further processing on command
	sub go {
		my @inputList = @_;
		my $inputLength = @inputList;

		#error checks: exit is in room, exit is unlocked
		if (defined $inputList[1] 
		    && $currentRoom->exitRefExists($inputList[1]))
		{
		    if (!$currentRoom->getExitLocked($inputList[1]))
			{
				$currentRoom = $currentRoom->getExitRoom($inputList[1]);
			
				print wrap("","", $currentRoom->filledInDescription($otherItemsList));
			} else {
				print wrap("","", "$lockedDirError\n");
				return 1;
			}
		}else{
			if ($inputLength > 2)
			{
				return 0;
			} else {
				print wrap("","", "$invalidDirError\n");
				return 1;
			}
		}
	}
	
	#post: outputs the result of the user typing look, and possibly an item/exit
	#arguments:
	#	@_: the users input, with each word in a different index
	#returns: 1 if displayed output, 0 if there should be further processing on command
	sub look {
		my @inputList = @_;
		my $inputLength = @inputList;

		#if command is simply "look" -> print out room description
		if ($inputLength == 1){
			print wrap("","", $currentRoom->filledInDescription($otherItemsList));
			return 1;
		}else{
			#the item being looked at is in the room
			if ($currentRoom->itemExists($inputList[1])){
				print wrap("","",  $currentRoom->getItem($inputList[1])->lookDescription);
				return 1;
			}
			#the item being looked at is in the inventory
			elsif (exists($inventory{$inputList[1]})){
				print wrap("","",  $inventory{$inputList[1]}->heldDescription);
				return 1;
			}
			#an exit is being looked at
			elsif ($currentRoom->exitRefExists($inputList[1])){
				if ($currentRoom->getExitLocked($inputList[1])) {
					print wrap("","",  $currentRoom->getExitLockedDescr($inputList[1]));
					return 1;
				}
				else {
					print wrap("","", $currentRoom->getExitDescr($inputList[1]));
					return 1;
				}
			}
			#the user is trying to look at something that doesn't exist
			else{
				if ($inputLength > 2)
				{
					return 0;
				} else {
					print wrap("","", "$invalidLookError\n");
					return 1;
				}
			}
		}
	}
	
	#post: outputs the result of the user typing get and an item, changing the $currentRoom's item list and @inventory as needed
	#arguments:
	#	@_: the users input, with each word in a different index
	#returns: 1 if displayed output, 0 if there should be further processing on command
	sub get {
		my @inputList = @_;
		my $inputLength = @inputList;
	
		if ($inputLength > 1)#the user did give an item name
		{
			if ($currentRoom->itemExists($inputList[1]))
			{
				#if in room and take-able, removes from room and adds to inventory
				my $myItem = $currentRoom->getItem($inputList[1]);
				if ($myItem->canTake)
				{
					$inventory{$inputList[1]} = $myItem;
					$currentRoom->deleteItem($inputList[1]);
					print wrap("","", "You take the $inputList[1].");
					return 1;
				}
				else
				{
					print wrap("","", "$invalidTakeCantTakeError\n");
					return 1;
				}
			}else
			{
				if ($inputLength > 2)
				{
					return 0;
				} else {
					print wrap("","", "$invalidTakeUnseenError\n");
					return 1;
				}
			}
		}else
		{
			print wrap("","", "$takeNoItemSpecifiedError\n");
			return 1;
		}
	}
	
	#post: outputs the result of the user typing drop and an item, changing the $currentRoom's item list and @inventory as needed
	#arguments:
	#	@_: the users input, with each word in a different index
	#returns: 1 if displayed output, 0 if there should be further processing on command
	sub drop {
		my @inputList = @_;
		my $inputLength = @inputList;
	
		if ($inputLength > 1)#the user did give an item name
		{
			if (exists $inventory{$inputList[1]})
			{
				#if in room and drop-able, removes from room and adds to inventory
				my $myItem = $inventory{$inputList[1]};
				if ($myItem->droppable)
				{
					$currentRoom->setItem(lc ($myItem->name), $myItem);
					delete $inventory{$inputList[1]};
					print wrap("","", "You drop the $inputList[1].");
					return 1;
				}
				else
				{
					print wrap("","", "$invalidDropCantDropError\n");
					return 1;
				}
			}else
			{
				if ($inputLength > 2)
				{
					return 0;
				} else {
					print wrap("","", "$invalidDropNonExistentError\n");
					return 1;
				}
			}
		}else
		{
			print wrap("","", "$dropNoItemSpecifiedError\n");
			return 1;
		}
	}
	
	#post: processes unique commands, and carries out their effects
	#arguments:
	#	@_: the users input, with each word in a different index
	#returns: a list:
	#		[0]: 1 if a valid command, 0 otherwise
	#		[1]: the next word that has to be matched (for example, 1 would be trying to match item1)
	sub uniqueCommands {		
		my %combinedHash = (%inventory, %{$currentRoom->itemHash});
		my $tryToMatch = 0;
	
		while ( my ($itemName, $item) = each %combinedHash) {
			if (not $item->noCommands) {
			
				my @input = @_;
				my $l = @input;
				
				#add empty strings to @input until at least four elements long
				#this greatly simplifies checking a command is valid, below
				while ($l < 4)
				{
					@input = (@input, "");
					$l += 1;
				}
				
				#checks the command exists in the item currently being check
				if ($item->commandExists($input[0])){
					$tryToMatch = List::Util::max $tryToMatch, 1;

					my ($itemHash1, $itemHash2);

					#creates a sub ref to get hash for location of the first and second item
					#arguments:
					#	$_[0] = the location name ("IN INVENTORY" or other for in room)
					#returns: the appropriate hash reference
					my $itemHashGetter = sub {
						if ($_[0] eq "IN_INVENTORY")
						{
							return \%inventory;
						}
						else
						{
							return $currentRoom->itemHash;
						}
					};
					
					$itemHash1 = &$itemHashGetter($item->getCommandLocation1($input[0]));
					$itemHash2 = &$itemHashGetter($item->getCommandLocation2($input[0]));
					
					#check the conditions for the command are met
					if ($item->getCommandItem1($input[0]) eq $input[1]){
						$tryToMatch = List::Util::max $tryToMatch, 2;
						if ($item->checkMiddleWordValid($input[0], $input[2])){
							$tryToMatch = List::Util::max $tryToMatch, 3;
							if ($item->getCommandItem2($input[0]) eq $input[3]) {
							{
								if (($input[1] eq "" || exists $itemHash1->{$input[1]})
									&& ($input[3] eq "" || exists $itemHash2->{$input[3]}))
									{
										#if the conditions are met, print the descriptions, and carry out the effects
										print wrap("","", $item->getCommandDescription($input[0]));
										
										my $effect = $item->getCommandEffect($input[0]);
										
										if($effect =~ /REMOVE1(\||$)/){							
											delete $itemHash1->{$item->getCommandItem1($input[0])};
										}
										
										if($effect =~ /REMOVE2(\||$)/){
											delete $itemHash2->{$item->getCommandItem2($input[0])};
										}
										
										if ($effect =~ /ADD_TO_ROOM:([0123456789,]*)(\||$)/){
											my @numList = split(",",$1);
											my @itemList = $item->getCommandEffectItems($input[0]);
											
											for my $i (@numList)
											{
												$currentRoom->itemHash->{$itemList[$i]->name} = $itemList[$i];
											}
										}
										
										if($effect =~ /ADD_TO_INVENTORY:([0123456789,]*)(\||$)/){
											my @numList = split(",",$1);
											my @itemList = $item->getCommandEffectItems($input[0]);
											
											for my $i (@numList)
											{
												$inventory{$itemList[$i]->name} = $itemList[$i];
											}
										}
										
										if($effect =~ /OPEN_EXIT:(.*?)(\||$)/){
											my @nameList = split(",", $1);
											
											for my $i (@nameList)
											{
												$currentRoom->setExitLocked($i, 0);
											}
										}
										
										if($effect =~ /LOCK_EXIT:(.*)(\||$)/){
											my @nameList = split(",", $1);
											
											for my $i (@nameList)
											{
												$currentRoom->setExitLocked($i, 1);
											}
										}
										
										if($effect =~ /GOTO_EXIT:(.*)(\||$)/){
										if ($currentRoom->exitRefExists(lc $1))
											{
												print "\n\n";
												go("", lc $1);
											}
										}
										
										return (1, $tryToMatch);
									}
								}
							}
						}
					}
				}
			}
		}
		
		return (0, $tryToMatch);
	}
	
	#arguments:
	#	$_[0] = gameLayout.txt full relative location
	#	$_[1] = reference to the hash for commands
	#returns:
	#	$_[0] = the starting rooms file
	#	$_[1] = the ending rooms file
	#	$_[2] = the ending description
	#	$_[3] = the help text
	sub readStartFile {
		my $fileName = shift;
		my $commandRef = shift;
		my $fileReader = ReadFromFile->new;
		
		my ($startingRoom, $endingRoom, $endingDescr, $help);
		
		open(my $fh, "<", $fileName)
			or die("The file $fileName does not exist.\n");
			
		local $/ = ";";
			
		my @slurp = <$fh>;
		
		for my $line (@slurp)
		{
			$line = $fileReader->removeUnneeded($line);
		
			my $val;
			
			#creates a sub to get the commands for a given action
			#args:
			#	$_[0] = possible commands, separated by ":"
			#	$_[1] = a value
			#returns:
			#	returns a hash with all the action words (from $_[0]) mapped to the value in $_[1]
			my $getCmds = sub {
				my $val = $_[0];
				my $attrib;
				my $end = ":";
				
				do {
					($val, $attrib, $end) = $fileReader->getPropertyAndEnd($val);
						
					$commandRef->{ $attrib } = $_[1];
				} while ($end eq ":")
			};

			#finds each attribute in the provided item file
			if ($fileReader->processStringPropertiesVars($line,
														 $gameName, "name",
														 $startingRoom, "startingRoom",
														 $startDescription, "startingDescription",
														 $endingRoom, "endingRoom",
														 $endingDescr, "endingDescription",
														 $help, "help",
														 $prompt, "prompt",
														 $inventoryName, "inventoryName",
														 $otherItemsList, "otherItemsList",
														 $invalidDirError, "invalidDirError",
														 $lockedDirError, "invalidLockedError",
														 $invalidLookError, "invalidLookError",
														 $invalidTakeUnseenError, "invalidTakeUnseenError",
														 $invalidTakeCantTakeError, "invalidTakeCantTakeError",
														 $takeNoItemSpecifiedError, "takeNoItemSpecifiedError",
														 $invalidDropCantDropError, "invalidDropCantDropError",
														 $invalidDropNonExistentError, "invalidDropNonExistentError",
														 $dropNoItemSpecifiedError, "invalidDropNoItemSpecifiedError",
														 $invalidCommandError, "invalidCommandError")){}
			elsif($val = $fileReader->processBoundedProperty($line, "lookCmds", "{", "}"))
			{
				&$getCmds($val, "look");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "getCmds", "{", "}"))
			{
				&$getCmds($val, "get");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "dropCmds", "{", "}"))
			{
				&$getCmds($val, "drop");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "goCmds", "{", "}"))
			{
				&$getCmds($val, "go");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "invCmds", "{", "}"))
			{
				&$getCmds($val, "inv");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "helpCmds", "{", "}"))
			{
				&$getCmds($val, "help");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "quitCmds", "{", "}"))
			{
				&$getCmds($val, "quit");
			}
			elsif($val = $fileReader->processBoundedProperty($line, "startingInventory", "{", "}"))
			{		
				my $attrib;
				my $end = ":";
				
				while ($end eq ":"){
					($val, $attrib, $end) = $fileReader->getPropertyAndEnd($val);
										
					my $item = Item->new(fileName => $attrib);
					$inventory{lc $item->name} = $item;	
				}
			}
			else
			{
				$fileReader->processUncaughtLine($fileName, $line);
			}
		}
				
		return ($startingRoom, $endingRoom, $endingDescr, $help);
	}
}