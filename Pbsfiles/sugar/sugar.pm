NoDigest qr/\.java$/, qr/\.test$/ ;

sub Module { AddSubpbsRule @_ } 
sub MyAddRule { AddRule @_ } 

sub get_modules {map { "$_/$_" } map { split '\s+'} GetConfig(@_) // () }
sub get_tests {map { "$_/$_.test" } map {split '\s+'} GetConfig(@_) // ()}

1 ;
