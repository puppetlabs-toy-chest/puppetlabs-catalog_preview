class catalog_preview::examples::string_number_in_comparison {
  
  if ( '6' in [ 5, 6, 7] ) {
    notify { 'This matches on current parser but not future' : }
  }

}
