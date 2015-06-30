class catalog_preview::examples::escaping_with_backslashes {

  $double_backslash = 'this is a backslash \\'
  
  notify { "${double_backslash}" : } 

  $tab_escape = '\this is a backslash'

  notify { "${tab_escape}" : }

}
