visualize_wf <- function(data, custom_title){
  
asian <- data %>%
  filter(group == "Asian Americans") %>%
  mutate(diff = Collective_gain - Collective_loss) %>%
  ggplot(aes(x = fct_reorder(bigram, diff), y = diff)) +
  geom_col() +
  coord_flip() +
  labs(title = {{custom_title}},
       subtitle = "Asian Americans",
       x = "Bigrams",
       y = "# of Collective Gain - # of Collective Loss") 

black <- data %>%
  filter(group != "Asian Americans") %>%
  mutate(diff = Collective_gain - Collective_loss) %>%
  ggplot(aes(x = fct_reorder(bigram, diff), y = diff)) +
  geom_col() +
  coord_flip() +
  labs(subtitle = "African Americans",
     x = "Bigrams",
     y = "# of Collective Gain - # of Collective Loss")

asian / black
}

# The following tidy_text function heavily draws on https://www.tidytextmining.com/ngrams.html

tidy_text <- function(data, var1, var2){
  
  # Clean sources 
  data$source <- gsub('[[:digit:]]', '', data$source) 
  data$source <- gsub('[[:punct:]]+', '', data$source) %>% trimws()
  
  # Clean text
  data <- clean_text(data)
  
  # Filter
  data <- data %>%
    filter({{var1}} == 1 | {{var2}} ==1)
  
  # Mutate 
  data <- data %>%
    mutate(linked_fate = {{var1}} - {{var2}}) %>%
    mutate(linked_fate = case_when(linked_fate == "1" ~ "Collective_gain",
                                   linked_fate == "-1" ~ "Collective_loss",
                                   TRUE ~ as.character(linked_fate)))
  
  # Remove stop words; This part of code comes from Mhairi McNeill:https://stackoverflow.com/a/37526926
  
  stopwords <- paste(tm::stopwords('en'), collapse = "\\b|\\b")
  
  stopwords_regex <- paste0("\\b", stopwords, "\\b")
  
  data$text <- gsub(stopwords_regex, "", data$text)
  
  data 
  
}

tokenize_text <- function(data){
  
  data %>%
    # tokenize
    unnest_tokens(bigram, text, token = "ngrams", n = 2)
  
}

create_word_frequency <- function(data){
  
  data %>%
    group_by(linked_fate, group) %>%
    count(bigram, sort = TRUE) %>%
    # Select only interested columns
    select(linked_fate, group, bigram, n)
  
}


filter_n <- function(data){
  
  asian_lp <- data %>% filter(group == "Asian Americans", linked_fate == "Collective_gain") 

  asian_lh <- data %>% filter(group == "Asian Americans", linked_fate != "Collective_gain") 

  asian_lp <- asian_lp %>% arrange(desc(n)) %>% head(15) 
  
  asian_lh <- asian_lh %>% arrange(desc(n)) %>% head(15) 
  
  black_lp <- data %>% filter(group != "Asian Americans", linked_fate == "Collective_gain") 

  black_lh <- data %>% filter(group != "Asian Americans", linked_fate != "Collective_gain") 
  
  black_lp <- black_lp %>% arrange(desc(n)) %>% head(15) 
  
  black_lh <- black_lh %>% arrange(desc(n)) %>% head(15)
  
  asian <- bind_rows(asian_lp, asian_lh) 
  black <- bind_rows(black_lp, black_lh) 
  
  bind_rows(asian, black) %>%
    spread("linked_fate", "n") %>%
    replace(is.na(.), 0)
  
}

filter_words <- function(data){
  
  data %>%
    mutate(etc = as.numeric(str_detect(bigram, "year|years|san|francisco|oakland|washington|th|street|month|months|week|weeks|western|california|united|los|international|district|hong|west|first|second|new york|per cent|alameda|county|bay area|mr|dont know|will|sun reporter|east bay|men women|contra costa|make sure|can get|berkeley|early|community|park|junior|student|dont want|university|task force|association|man|american|americans|pacific|asian|chinese|black|school"))) %>%
    filter(etc != 1)
  
}

clean_text <- function(data){
  
  data <- data %>%
    mutate(text = tolower(text),
           text = str_replace_all(text, '[\r?\n]',''),
           text = str_replace_all(text, '[^\\w\\s]',''),
           text = str_replace_all(text, '\\d+', ''),
           text = trimws(text),
           postID = row_number())
  
  return(data)
}

create_sparse_matrix <- function(data){
  data <- data %>%
    unnest_tokens(word, text) %>%
    anti_join(get_stopwords()) %>%
    filter(!str_detect(word, "[0-9]+")) %>%
    add_count(word) %>%
    filter(n > 100) %>%
    select(-n) %>%
    count(postID, word) %>%
    cast_sparse(postID, word, n)
}

visualize_diagnostics <- function(sparse_matrix, many_models){
  
  heldout <- make.heldout(sparse_matrix)
  
  k_result <- many_models %>%
    mutate(exclusivity = map(topic_model, exclusivity),
           semantic_coherence = map(topic_model, semanticCoherence, sparse_matrix),
           eval_heldout = map(topic_model, eval.heldout, heldout$missing),
           residual = map(topic_model, checkResiduals, sparse_matrix),
           bound =  map_dbl(topic_model, function(x) max(x$convergence$bound)),
           lfact = map_dbl(topic_model, function(x) lfactorial(x$settings$dim$K)),
           lbound = bound + lfact,
           iterations = map_dbl(topic_model, function(x) length(x$convergence$bound)))
  
  k_result %>%
    transmute(K,
              `Lower bound` = lbound,
              Residuals = map_dbl(residual, "dispersion"),
              `Semantic coherence` = map_dbl(semantic_coherence, mean),
              `Held-out likelihood` = map_dbl(eval_heldout, "expected.heldout")) %>%
    gather(Metric, Value, -K) %>%
    ggplot(aes(K, Value, color = Metric)) +
    geom_line(size = 1.5, alpha = 0.7, show.legend = FALSE) +
    facet_wrap(~Metric, scales = "free_y") +
    labs(x = "K (number of topics)",
         y = NULL,
         title = "Model diagnostics by number of topics")}

visualize_year_trends <- function(data){
  
  data %>%
    gather(linked_fate, value, lp_exclusive, lh_exclusive, lf_mixed) %>%
    ggplot(aes(x = year, y = value, col = linked_fate)) +
    stat_summary(fun.y = mean, geom = "line") +
    stat_summary(fun.data = mean_se, geom = "ribbon", fun.args = list(mult= 1.96), alpha = 0.1) +
    scale_y_continuous(labels = scales::percent) +
    scale_color_manual(name = "Type", labels = c("Mixed","Collective loss","Collective gain"), values=c("purple","red","blue")) +
    labs(title = "Yearly trends", 
         caption = "Source: Ethnic Newswatch",
         y = "Proportion of articles", x = "Publication year") 
  
}


visualize_month_trends <- function(data){
  
  data %>%
    gather(linked_fate, value, lp_exclusive, lh_exclusive, lf_mixed) %>%
    ggplot(aes(x = anytime::anydate(year_mon), y = value, col = linked_fate)) +
    stat_summary(fun.y = mean, geom = "line") +
    stat_summary(fun.data = mean_se, geom = "ribbon", fun.args = list(mult= 1.96), alpha = 0.1) +
    scale_x_date(date_labels = "%Y-%m") +
    scale_y_continuous(labels = scales::percent) +
    scale_color_manual(name = "Type", labels = c("Mixed","Collective loss","Collective gain"), values=c("purple","red","blue")) +
    labs(title = "Monthly trends", 
         caption = "Source: Ethnic Newswatch",
         y = "Proportion of articles", x = "Publication month") 
  
}

visualize_matched <- function(data){
  
  data %>%
    gather(linked_fate, value, lp_exclusive, lh_exclusive, lf_mixed) %>%
    mutate(linked_fate == factor(linked_fate, levels = c("lh_exclusive", "lf_mixed", "lp_exclusive"))) %>%
    ggplot(aes(x = fct_reorder(group, value), y = value, fill = linked_fate)) +
    stat_summary(fun.y = mean, geom = "bar", stat = "identity", position ="dodge", color = "black") +
    stat_summary(fun.data = mean_se, geom = "errorbar", position = "dodge", fun.args = list(mult= 1.96)) +
    #  ylim(c(0,17)) +
    labs(title = "Matched comparison (1976-1981)", y = "Proportion of articles", x = "Group") +
    scale_fill_manual(name = "Type", labels = c("Mixed","Collective loss","Collective gain"), values=c("purple","red","blue")) +
    scale_y_continuous(labels = scales::percent)
  
}

visualize_ratio <- function(data){
  data %>%
    gather(linked_fate, value, lp_exclusive, lh_exclusive, lf_mixed) %>%
    group_by(group, linked_fate, type) %>%
    summarize(mean = mean(value)) %>%
    spread(linked_fate, mean) %>%
    mutate(lp_ratio = lp_exclusive / lh_exclusive,
           lh_ratio = lh_exclusive / lp_exclusive) %>%
    select(group, type, lp_ratio, lh_ratio) %>%
    gather(ratio, value, c(lp_ratio, lh_ratio)) %>%
    ggplot(aes(group, value, fill = ratio)) +
    geom_bar(stat="identity", color="black", 
             position=position_dodge()) +
    facet_wrap(~type) +
    scale_fill_manual(name = "Type", labels = c("Hurt/Progrress ratio","Prgress/Hurt ratio"), values=c("red","blue")) 
}

visualize_ratio_source <- function(data){
  data %>%
    gather(linked_fate, value, lp_exclusive, lh_exclusive, lf_mixed) %>%
    group_by(source, linked_fate, type) %>%
    summarize(mean = mean(value)) %>%
    spread(linked_fate, mean) %>%
    mutate(lp_ratio = lp_exclusive / lh_exclusive,
           lh_ratio = lh_exclusive / lp_exclusive) %>%
    select(source, type, lp_ratio, lh_ratio) %>%
    gather(ratio, value, c(lp_ratio, lh_ratio)) %>%
    ggplot(aes(type, value, fill = ratio)) +
    geom_bar(stat="identity", color="black", 
             position=position_dodge()) +
    facet_wrap(~source) +
    scale_fill_manual(name = "Type", labels = c("Hurt/Progrress ratio","Prgress/Hurt ratio"), values=c("red","blue")) 
}

summarize_content <- function(data){
  
  data %>%
    summarize(mean = mean(value),
              sd  = sd(value),
              n = n()) %>%
    mutate(se = sd / sqrt(n), # calculate standard errors and confidence intervals 
           lower.ci = mean - qt(1 - (0.05 / 2), n - 1) * se,
           upper.ci = mean + qt(1 - (0.05 / 2), n - 1) * se)
  
}

visualize_aggregated <- function(data){
  
  data %>%  
    summarize(mean = mean(value),
              sd  = sd(value),
              n = n()) %>%
    mutate(se = sd / sqrt(n), # calculate standard errors and confidence intervals 
           lower.ci = mean - qt(1 - (0.05 / 2), n - 1) * se,
           upper.ci = mean + qt(1 - (0.05 / 2), n - 1) * se) %>%
    ggplot(aes(x = fct_reorder(type, mean), y = mean, fill = linked_fate)) +
    geom_bar(stat="identity", color="black", 
             position=position_dodge()) +
    geom_errorbar(aes(ymin= lower.ci, ymax = upper.ci), width=.2,
                  position=position_dodge(.9)) +
    facet_wrap(~source) +
    scale_fill_manual(name = "Type", labels = c("Mixed","Linked hurt","Linked progress"), values=c("purple","red","blue")) +
    scale_y_continuous(labels = scales::percent)
  
}

visualize_comp <- function(data){
  
  data %>%  
    summarize(mean = mean(value),
              sd  = sd(value),
              n = n()) %>%
    mutate(se = sd / sqrt(n), # calculate standard errors and confidence intervals 
           lower.ci = mean - qt(1 - (0.05 / 2), n - 1) * se,
           upper.ci = mean + qt(1 - (0.05 / 2), n - 1) * se) %>%
    ggplot(aes(x = fct_reorder(type, mean), y = mean, fill = linked_fate)) +
    geom_bar(stat="identity", color="black", 
             position=position_dodge()) +
    geom_errorbar(aes(ymin= lower.ci, ymax = upper.ci), width=.2,
                  position=position_dodge(.9)) +
    facet_wrap(~source) +
    scale_y_continuous(labels = scales::percent)
  
}

visualize_performance <- function(data){
  
  data %>%
    ggplot(aes(x = fct_reorder(models, rate), y = rate, fill = metrices)) +
    geom_col(position = "dodge") +
    facet_grid(measure ~ group) +
    ylim(c(0, 1)) +
    coord_flip() +
    scale_y_continuous(labels = scales::percent) 
  
}