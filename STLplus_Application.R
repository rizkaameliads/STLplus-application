# Libraries
# install.packages("stlplus")
library(tidyverse)
library(dplyr)
library(devtools)
library(stlplus)
library(ggfortify)
library(xts)
library(lubridate)

# Hydrology Data in CSV
df <- read.csv("D:\\01. RIZKA\\Repo__GitHub\\4_STLplus\\GRACE_CSR_2002.04_2024.09.csv",
               sep=",")
df$time <- as.Date(df$time)
head(df)

# Execute for one grid only (for simple practice)
df1 <- subset(df, lat == "-7.625" & lon == "110.875")
str(df1)

# Check the start and end date of df1
head(df1)
tail(df1)

# Add date column with data format "Y-m-01" to check double values in a month
df1$date <- as.Date(format(df1$time, "%Y-%m-01"))
# Check duplicate
df1[duplicated(df1$date), ]

df1$date[duplicated(df1$date)] <- df1$date[duplicated(df1$date)] %m+% months(1)

# Visualize missing data
df1$month <- as.character(format(df1$date, "%m"))
df1$month <- factor(
  month.abb[as.numeric(df1$month)], 
  levels = month.abb)
df1$year <- as.character(format(df1$time, "%Y"))
# Tile
ggplot(df1, aes(year, month))+
  geom_tile(aes(fill = lwe_cm), color = "white") +
  scale_fill_distiller(palette = "RdYlBu", direction = 1, limits = c(-30,30),
                       name = "EWH (cm)") +
  labs(x = "Year", y = "Month") +
  theme(
    #panel.grid = element_blank(),
    legend.text = element_text(size = 11),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "right"
  )

# Make dummy DataFrame
start_date <- as.Date("2002-04-01")
end_date <- as.Date("2024-09-30")
date_seq <- seq.Date(from = start_date, to = end_date, by = "month")
date_seq <- tibble(date = date_seq)

# Merge
df2 <- left_join(x = date_seq, y = df1, by = "date" )
str(df2)

# Time-series
df2 %>% ggplot(aes(date, lwe_cm))+
  geom_line(linewidth=.75,color ="steelblue")+
  geom_point(size=2,shape=1,color="steelblue")+
  labs(title="TWSA in Java Island",
       subtitle = "Longitude: 110.875; Latitude: -7.625", 
       x= "Time", y="EWH (cm)")

# Perform STLplus
df2_ts <- ts(df2$lwe_cm,
             start = c(2002, 4), 
             frequency = 12)
df2_ts

# Time series object
# stlobj <- stlplus(df2_ts, s.window=12, s.degree=2, 
#                   t.window=12, t.degree=2, fc.window=12)
stlobj <- stlplus(df2_ts, s.window="periodic")

# Extract decomposed signals
trend <- trend(stlobj)
seasonal <- seasonal(stlobj)
remainder <- remainder(stlobj)

# Mutate in df
df3 <- df2 %>%
  mutate(trend = trend,
         seasonal = seasonal,
         remainder = remainder)
head(df3)

# Calculate mean for seasonal and remainder signals
df3$month <- as.character(format(df3$date, "%m"))
df3$month <- factor(
  month.abb[as.numeric(df3$month)], 
  levels = month.abb)
df3 <- df3 %>%
  group_by(month) %>%
  mutate(meanSeas = mean(seasonal, na.rm = TRUE),
         meanRema = mean(remainder, na.rm = TRUE)) 
head(df3)

# Which na?
missing_indices <- which(is.na(df3$lwe_cm))
missing_indices
length(missing_indices)

# Fill in
reconstruct_stl <- df3$trend + df3$meanSeas + df3$meanRema
df3_recon <- df3 %>%
  ungroup() %>%  # Remove grouping to ensure global replacement
  mutate(lwe_cm = replace(lwe_cm, is.na(lwe_cm), reconstruct_stl[missing_indices]))
head(df3_recon)

# Visualize
ggplot()+
  geom_line(data = df3_recon, aes(x=date, y=lwe_cm), size=.75,color ="red")+
  geom_point(data = df3_recon, aes(x=date, y=lwe_cm), size=2,shape=1,color="red")+
  geom_line(data = df3, aes(x=date,y=lwe_cm),size=.75,color="steelblue")+
  geom_point(data = df3, aes(x=date, y=lwe_cm), size=2,shape=1,color="steelblue")+
  labs(title="TWSA in Java Island",
       subtitle = "Longitude: 110.875; Latitude: -7.625", x= "Time", y="EWH (cm)")

# validate stl with TMAA
TMAA <- read.csv("D:\\01. RIZKA\\Repo__GitHub\\4_STLplus\\WaterLevelData.csv",
                 sep=";")
TMAA$date <- as.Date(TMAA$date)
head(TMAA)

# Merge with df3_recon
df3_validate <- left_join(df3_recon[,c("date","lwe_cm")], TMAA, by = "date")
df3_validate

# Shift WLA
df3_validate <- df3_validate %>%
  mutate(WLA_1 = lag(WLA, n=1),
         WLA_2 = lag(WLA, n=2),
         WLA_3 = lag(WLA, n=3),
         WLA_4 = lag(WLA, n=4),
         WLA_5 = lag(WLA, n=5))
df3_validate

# Calculate correlation
corr <- cor(df3_validate[,c(2:8)], use="pairwise.complete.obs")
corr

# Visualize
ggplot(df3_validate, aes(x = date)) +
  geom_line(aes(y = lwe_cm, color = "GRACE TWSA in centimeters")) +  
  geom_line(aes(y = WLA_2 * 10, color = "Water Level Data in meters")) +  
  scale_y_continuous(
    name = "EWH (cm)", 
    sec.axis = sec_axis(~ . / 10, name = "WLA (m)")  
  ) +
  scale_color_manual(values = c("GRACE TWSA in centimeters" = "blue", 
                                "Water Level Data in meters" = "red"))+
  theme(legend.position = "bottom")

# Subset only at 11 month gaps
longest_gaps <- subset(df3_validate, 
                       date >= "2017-07-01" & date <= "2018-05-01")
longest_gaps

# Visualize
ggplot(longest_gaps, aes(x = date)) +
  geom_line(aes(y = lwe_cm, color = "GRACE TWSA in centimeters")) +  
  geom_line(aes(y = WLA_2 * 10, color = "Water Level Data in meters")) +
  scale_y_continuous(
    name = "EWH (cm)", 
    sec.axis = sec_axis(~ . / 10, name = "WLA (m)") 
  ) +
  scale_color_manual(values = c("GRACE TWSA in centimeters" = "blue", 
                                "Water Level Data in meters" = "red"))+
  theme(legend.position = "bottom")

# Calculate correlation
corr_longest_gaps <- cor(longest_gaps[,c("lwe_cm","WLA_2")])
corr_longest_gaps