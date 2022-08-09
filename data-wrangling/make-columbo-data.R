library(tidyverse)
library(rvest)

# This page gets me the series overview and the pilot episodes with descriptions
# BUT the individual season tables don't seem to have the descriptions with them
raw_seasons <-
  read_html('https://en.wikipedia.org/wiki/List_of_Columbo_episodes') |>
  html_elements(".wikitable") |>
  html_table()

raw_overview <- raw_seasons[[1]]
raw_pilots <- raw_seasons[[2]]

# These pages gets me the individual season episodes with their descriptions
raw_seasons_with_descriptions <-
  glue::glue("https://en.wikipedia.org/wiki/Columbo_(season_{1:10})") |>
  map(~read_html(.x, encoding = "latin1") |>
        html_element(".wikitable") |>
        html_table())

# Create look-up vector to rename columns ----------------------------------
# Get every unique column title in all tables
all_colnames <- c(colnames(raw_pilots), map(raw_seasons_with_descriptions, colnames) |> unlist()) |> unique()

colnames_lookup <-
  setNames(
    c(
      "episode_index",
      "title",
      "directed_by",
      "written_by",
      "murderer_played_by",
      "victim_played_by",
      "original_air_date",
      "run_time",
      "",
      "episode",
      "victim_played_by",
      "run_time",
      "murderer_played_by"),
    all_colnames)


# Wrangle the pilot episodes to a tidy tibble -----------------------------
pilots <-
  raw_pilots |>
  select(-"") |>
  rename_with(~colnames_lookup[.x]) |>
  filter(row_number() %% 2 == 1) |>
  bind_cols(
    raw_pilots |>
      select(-"") |>
      rename_with(~colnames_lookup[.x]) |>
      filter(row_number() %% 2 == 0) |>
      select(description = episode_index)) |>
  mutate(episode = episode_index,
         season = "0")

# Wrangle season 1-10 episodes to a tidy tibble ---------------------------
season_1to10 <-
  map_dfr(raw_seasons_with_descriptions,
        ~ .x |>
          select(-"") |>
          rename_with(~colnames_lookup[.x]) |>
          filter(row_number() %% 2 == 1) |>
          bind_cols(
            .x |>
              select(-"") |>
              rename_with(~colnames_lookup[.x]) |>
              filter(row_number() %% 2 == 0) |>
              select(description = episode_index)),
        .id="season")

# When does Columbo appear? -----------------------------------------------
# Data from Mark Longair
raw_ml <- read_csv('raw-data/columbo-first-appearances-mark-longair.csv')

ml <-
  raw_ml |>
  arrange(Code) |>
  select(columbo_first_appearance = `First appearance of Columbo`,
         run_time_ml = `Total Length`,
         occupation_of_murderer = `Occupation of murderer`) |>
  mutate(episode_index = as.character(row_number()),
         columbo_first_appearance = as.numeric(columbo_first_appearance),
         run_time_ml = as.numeric(run_time_ml))

# Wrangle the oveview table -----------------------------------------------
overview <- raw_overview
colnames(overview) <- overview[1,] |> unlist()

overview <-
  overview[-1, -2] |>
  rename(season = Season,
         episodes = Episodes,
         first_aired = `First aired`,
         last_aired = `Last aired`,
         network = Network) |>
  mutate(season = case_when(season == "Pilots" ~ "0",
                            season == "10 + specials" ~ "10",
                            TRUE ~ season),
         first_aired = lubridate::ymd(str_extract(first_aired, "[0-9]{4}-[0-9]{2}-[0-9]{2}")),
         last_aired = lubridate::ymd(str_extract(last_aired, "[0-9]{4}-[0-9]{2}-[0-9]{2}")))

# Combine all data sources ------------------------------------------------
all_out <-
  pilots |>
  bind_rows(season_1to10) |>
  left_join(ml, by = "episode_index") |>
  left_join(overview |> select(season, network), by = "season") |>
  mutate(episode_index = as.numeric(episode_index),
         episode = as.numeric(episode),
         season = as.numeric(season),
         title = str_remove_all(title, "\""),
         original_air_date = lubridate::ymd(str_extract(original_air_date, "[0-9]{4}-[0-9]{2}-[0-9]{2}")),
         run_time = as.integer(str_remove_all(run_time, "min"))*60) |>
  select(-run_time) |> # remove the wikipedia run_time
  rename(run_time = run_time_ml) |> # Use ML's run_time
  relocate(season, episode, episode_index) |>
  relocate(description, .after = last_col())

# deal with the odd characters in the written_by column (They follow the S, T and S/T)
Encoding(all_out$written_by) <- "unknown"
Encoding(all_out$title) <- "unknown"

all_out <-
  all_out |>
  mutate(written_by =
           written_by |>
           str_remove_all("â€Š") |>
           str_replace_all(";", "; ") |>
           str_replace_all(
             pattern = "S[:blank:]:|T[:blank:]:|S/T[:blank:]:",
             replacement = function(x){paste0("(", str_remove_all(x, ":|[:blank:]"), ")")}),
         title = str_replace(title, "Ã\u0089", "E"))

# Write CSV ---------------------------------------------------------------
write_csv(all_out, 'columbo_data.csv')
