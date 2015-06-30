class catalog_preview::examples::reg_expression_against_non_string {

  if 22 =~ /\d\d/ {
    notify { 'current parser will match!': }
  } else {
    notify { 'future parser will give compilation error!': }
  }

}
