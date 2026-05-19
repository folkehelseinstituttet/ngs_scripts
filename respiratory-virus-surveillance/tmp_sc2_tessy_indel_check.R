library(dplyr)
library(tidyr)
library(lubridate)
library(janitor)
source('SC2/SC2_SQLquery_BNCOVID19.R')
source('SC2/SC2_SQLquery_25-26.R')
sc2_indel_source <- if (exists('SC2db_v')) SC2db_v else SC2db
sc2_indel_date_col <- intersect(c('prove_tatt','PROVE_TATT','sample_date','Sampledate'), names(sc2_indel_source))[1]
sc2_indel_cols <- names(sc2_indel_source)[grepl('(frameshift|insertion|deletion)', names(sc2_indel_source), ignore.case=TRUE)]
sc2_tessy_col <- intersect(c('Tessy','tessy'), names(sc2_indel_source))[1]
sc2_indel_df <- sc2_indel_source %>% mutate(indel_plot_date=as.Date(.data[[sc2_indel_date_col]]), indel_month=floor_date(indel_plot_date,'month'), Tessy_group=as.character(.data[[sc2_tessy_col]])) %>% filter(!is.na(indel_month), !is.na(Tessy_group), trimws(Tessy_group)!='', Tessy_group!='Ukjent')
cat('Before mutation filtering (top counts)\n')
print(sc2_indel_df %>% count(Tessy_group, sort=TRUE) %>% head(12))
top_tessy <- sc2_indel_df %>% count(Tessy_group, sort=TRUE) %>% slice_head(n=6) %>% pull(Tessy_group)
sc2_indel_df <- sc2_indel_df %>% mutate(Tessy_group=ifelse(Tessy_group %in% top_tessy, Tessy_group, 'Other'))
sc2_long <- sc2_indel_df %>% pivot_longer(cols=all_of(sc2_indel_cols), names_to='mutation_col', values_to='mutation_raw') %>% filter(!is.na(mutation_raw), trimws(as.character(mutation_raw))!='') %>% separate_rows(mutation_raw, sep=';|,') %>% mutate(mutation_raw=trimws(as.character(mutation_raw))) %>% filter(mutation_raw!='', !tolower(mutation_raw) %in% c('na','n/a','none','no mutations','ikke_satt'))
cat('After mutation filtering (Tessy counts)\n')
print(sc2_long %>% count(Tessy_group, sort=TRUE))
