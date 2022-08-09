library(tidyverse)

d <- read_csv('columbo_data.csv')

# 69 episodes of Columbo
stopifnot(nrow(d) == 69)

# No missing values
stopifnot(sum(map_int(d, ~sum(is.na(.x)))) == 0)

# Number of episodes per season is correct
stopifnot(
  all((d %>% count(season) %>% pull(n)) ==  c(2,7,8,8,6,6,3,5,4,6,14)))
