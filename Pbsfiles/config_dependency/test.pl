
PbsUse 'config_dependent' ;
sub AddConfigDependentRule ;

ExcludeFromDigestGeneration('filter' => qr/filter$/);

AddConfig a => 2 ;

AddConfigDependentRule 'generated', ['generated' => 'filter']
	=>  'touch %FILE_TO_BUILD' ;

#~ AddRule 'generated', ['generated' => 'config_and_filter_cache']
	#~ =>  'touch %FILE_TO_BUILD' ;
	
#~ AddRule 'config_and_filter_cache', ['config_and_filter_cache' => 'filter',  \&matcher]
	#~ => \&cache_generator ;

