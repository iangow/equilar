#    user  system elapsed
#  60.678   2.379 303.467
dropbox.path <- path.expand("~/Dropbox/")

# The locations of the files that will be imported, as well as where the
# files created will be saved.

equilar.path <- paste(dropbox.path, "data/equilar/director/",sep="")

# A function to read in text files and clean them up a bit
getTemp <- function(suffix) {
  # Read in the text files with the data
  file.name <- paste(equilar.path, suffix,"_",i,".csv.gz",sep="")
  temp <- read.csv(file.name, as.is=TRUE, header=TRUE,
    na.strings=c("N/A","N/M"))

  # Replace periods (.) with underscores (_) in variable names
  names(temp) <- gsub("\\.+","_",names(temp),perl=TRUE)
  names(temp) <- gsub("_$","",names(temp),perl=TRUE)
  names(temp) <- gsub("123_R","123R",names(temp),perl=TRUE)
  names(temp) <- gsub("^Discloure_Flag$","Disclosure_Flag",names(temp),perl=TRUE)

  # Some earlier years are missing fields supplied in later years.
  # This code adds these fields, and makes them NA in earlier years
  temp$fileyear <- as.integer(i)
  if (suffix=="co_fin") {
    temp[,setdiff(names(co_fin),names(temp))] <- NA
  }
  return(temp)
}

# Loop through files for each year
# Initialize the variables
director <- co_fin <-NULL
for (i in 2013:2002) { # I go backwards, as later years have more variables.
    cat(paste("Year ",i,": director,", sep=""))
    director <- rbind(director, getTemp("director") )
    cat(" co_fin\n")
	co_fin <- rbind(co_fin, getTemp("co_fin"))
}

director$FY_End <- as.Date(director$FY_End)
director$Start_Date <- as.Date(director$Start_Date, format="%m/%d/%Y")
director$Term_End_Date <- as.Date(director$Term_End_Date, format="%m/%d/%Y")
names(director) <- tolower(names(director))
names(director) <- gsub("x_of_committees", "num_committees", names(director))

convertToLogical <- function(vector) {
    vector[vector=="Y"] <- TRUE
    vector[vector=="N"] <- FALSE
    as.logical(vector)
}

for (i in c("chairman", "vice_chairman",
            "lead_independent_director",
            "audit_committee_financial_expert")) {
    director[, i] <- convertToLogical(director[,i])
}
director$insider_outsider_related <- director$insider_oustider_affiliate
director$insider_oustider_affiliate <- NULL

names(co_fin) <- tolower(names(co_fin))
names(co_fin) <- gsub("^c34$", "split_data", names(co_fin))
co_fin$fy_end <- as.Date(co_fin$fy_end)
co_fin$cusip <- trimws(co_fin$cusip)

co_fin$shares_outstanding_date <- as.Date(co_fin$shares_outstanding_date)
co_fin$total_shareholder_return_1_yr <- as.numeric(co_fin$total_shareholder_return_1_yr)

# CUSIPs that are all Xs are no good
co_fin$cusip[grepl("^X+$", co_fin$cusip)] <- NA

# Save the files to a PostgreSQL database
# load(paste(equilar.path,"board.Rdata",sep=""))
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

# rs <- dbGetQuery(pg, "CREATE SCHEMA director")
rs <- dbWriteTable(pg, c("director","director"), director, row.names=FALSE, overwrite=TRUE)
rs <- dbWriteTable(pg, c("director","co_fin"), co_fin, row.names=FALSE, overwrite=TRUE)

# E. Floyd Kvamme has been a director of the Company since March 1995.
# Ernest von Simson has been a director of Brio since August 2000.
# Franklin J. Lunding, Jr. Age 55  1972
# Mr. Deng has also been a member of our board of directors since September 1999.
# Thomas F. Mendoza has served as a member of our board of directors since June 1999.
# Victor E. Parker, Jr. has served as a member of our board of directors since July 2000.
#
rs <- dbGetQuery(pg, "
    -- Fix some data issues
    UPDATE director.director SET start_date = (
      SELECT start_date FROM director.director
      WHERE equilar_id(director_id)=107
        AND director_id(director_id)=12 AND fileyear=2002)
    WHERE equilar_id(director_id)=107
      AND director_id(director_id)=12 AND fileyear=2003;

    UPDATE director.director SET start_date = (
      SELECT start_date FROM director.director
      WHERE equilar_id(director_id)=107
        AND director_id(director_id)=13 AND fileyear=2002)
    WHERE equilar_id(director_id)=107
      AND director_id(director_id)=13 AND fileyear=2003;

    UPDATE director.director SET start_date = (
      SELECT start_date FROM director.director
      WHERE equilar_id(director_id)=4775
        AND director_id(director_id)=8 AND fileyear=2002)
    WHERE equilar_id(director_id)=4775
      AND director_id(director_id)=8 AND fileyear=2003;

    UPDATE director.director SET start_date = (
      SELECT start_date FROM director.director
      WHERE equilar_id(director_id)=5069
        AND director_id(director_id)=8 AND fileyear=2003)
    WHERE equilar_id(director_id)=5069
      AND director_id(director_id)=8 AND fileyear=2002;

    UPDATE director.director SET start_date = (
      SELECT start_date FROM director.director
      WHERE equilar_id(director_id)=5069
        AND director_id(director_id)=9 AND fileyear=2003)
    WHERE equilar_id(director_id)=5069
      AND director_id(director_id)=9 AND fileyear=2002;

    UPDATE director.director SET start_date = (
      SELECT start_date FROM director.director
      WHERE equilar_id(director_id)=5069
        AND director_id(director_id)=10 AND fileyear=2003)
    WHERE equilar_id(director_id)=5069
      AND director_id(director_id)=10 AND fileyear=2002;

    SET maintenance_work_mem='1GB';
    CREATE INDEX ON board.director (company_id);
    CREATE INDEX ON board.co_fin (company_id);
")

sql <- paste(readLines("director/create_indexes.sql"), collapse="\n")
rs <- dbGetQuery(pg, sql)
sql <- paste(readLines("director/create_equilar_proxies.sql"), collapse="\n")
rs <- dbGetQuery(pg, sql)

sql <- "CREATE INDEX ON director.equilar_proxies (file_name)"
rs <- dbGetQuery(pg, sql)

rs <- dbDisconnect(pg)
rs <- dbUnloadDriver(PostgreSQL())
