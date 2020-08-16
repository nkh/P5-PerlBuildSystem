
# example of  pure perl rules as well as example using dependent matchers

PbsUse('Dependers/Matchers') ;

AddRule 'rule_1', [qr<\./all$> => '$path/muu/all', '$path/f1', '$path/a.o', '$path/muu/xxxxx.o'] ;

AddRule 'rule_2', [qr<\.o$> => '$path/$basename.c'] ;

AddRule 'rule_3', 
	[
		[sub{return(@_[4 .. 5])}] # creator
		
		 #~ => qr<\.c$> => # regex
		 #~ => sub{ $_[0] =~ qr<\.c$>} => # regex
		 #~ => AnyMatch(qr<\.c$>, qr<f1>) => # regex
		 #~ => CompositMatch
			#~ (
			  #~ AnyMatch(qr<\.c$>, qr<f1>)
			#~ , NoMatch(qr/xx/)
			#~ ) => # regex
		 => AndMatch(qr<\.c$>, NoMatch(qr/xx/)) => # regex
				#normal dependency definition
				# available: $path $basename $name $ext
				'$path/$basename.h',
				  
				[ # post depender
				sub
					{
					return([1, "hi_there2"], @_[5 .. 6])
					}
				],
				sub #depender
					{
					return([1, "hi_there1"], @_[5 .. 6])
					},
	] ;





