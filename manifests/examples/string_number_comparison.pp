class catalog_preview::examples::string_number_comparison {

  case "3.14" {
    3.14 :  {
      $variable = 'current parser compares strings and numbers'  
    }
    '3.14': { 
      $variable = 'future parser skips the first option because strings != numbers'
    }
  }

  notify { $variable : }

}
