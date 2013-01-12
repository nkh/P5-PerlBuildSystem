
PbsUse('Configs/Compilers/gcc') ;
PbsUse('./depend_on_all_configs') ;

AddRule 'yy', ['yy'], \&Builder, \&special_run_time_variable_dependency ;