
#' Process Scholar Search
#' Method that will also explore Semantic Scholar Articles
#' @param query 
#' @param query_max
#' @param totalPages
#' @param yearMin
#' @param yearMax
#' @param PublicationType
#' @param requirePDF
#' @param sortResults
#' @import rvest
#' @import dplyr
#' @import httr
#' @import jsonlite
#' @import magrittr
#' @return
#' @export
processScholarSearch<-function(query =NULL,
                               query_max=40000,
                               totalPages = 1000,
                               yearMin = NULL,
                               yearMax = NULL,
                               publicationTypes = list(),
                               requirePDF = TRUE,
                               sortResults = "relevance"){
  
  yearMax<-ifelse(is.null(yearMax), format(Sys.Date(),"%Y"),yearMax)
  yearMin<-ifelse(is.null(yearMin),"1900",yearMin)
  
  years<-list(min=as.numeric(yearMin),max=as.numeric(yearMax))
  
  article_total <- 0

  
  site<-"https://www.semanticscholar.org/"
  session<- html_session(site)
  
  #searching for information
  search_form<-session %>% 
    html_nodes("form") %>% 
    extract2(1) %>%
    html_form()%>%
    set_values('q'  = query)
  
  #get the results
  result<-submit_form(session,search_form)
  
  
  #SINGLE PAGE RESULT

  ### get the results on each page
  ## Below is the POST query that semantic scholar accepts
  # '{"queryString":"data science","page":1,"pageSize":10,"sort":"relevance","authors":[],"coAuthors":[],"venues":[],"yearFilter":null,"requireViewablePdf":false,"publicationTypes":[],"externalContentTypes":[]}'

  page_count <-1
  stop_count<-0
  res<-c()
  
  while(article_total < query_max & stop_count < query_max & page_count< totalPages){
    
    #body of post request
    post_request<-list(queryString="data science",
         page=page_count,
         pageSize=10,
         sort="relevance",
         authors=list(),
         coAuthors=list(),
         venues=list(),
         yearFilter=years,
         requireViewablePdf=requirePDF,
         publicationTypes=publicationTypes,
         externalContentTypes=list())

    #getting paper data
    paper_data<-POST("https://www.semanticscholar.org/api/1/search",
              content_type('application/json'),
              body = jsonlite::toJSON(post_request,auto_unbox = TRUE))
    
    if(paper_data$status_code != 200){
      stop("Something went wrong getting data from semnatic scholar")
    }
    
   
    #just do this once
    if(page_count == 1){
      total_papers<-content(paper_data)$totalResults
      total_pages<-content(paper_data)$totalPages
      if(total_papers < query_max){
        query_max<-total_papers
      }
    }
    
    paper_data_results<-content(paper_data)$results
    
    #api paper request - no need, don't get extra info
    #paper<-paste0("http://api.semanticscholar.org/v1/paper/",paper_data_results[[1]]$id)
    #GET(paper) #YASSSS
    
    
    for(i in 1:length(paper_data_results)){
      paperType <- ifelse(paper_data_results[[i]]$venue$text=="","Book","Journal Article")
      #making it fit into the rest of the adjutant load
      risResults<-data.frame(PMID=paper_data_results[[i]]$id,
                             YearPub=paper_data_results[[i]]$year$text,
                             Journal=paper_data_results[[i]]$venue$text,
                             Authors=paste(sapply(paper_data_results[[i]]$authors,function(x){x[[1]]$name}),collapse=", "),
                             Title=paper_data_results[[i]]$title$text,
                             Abstract=paper_data_results[[i]]$paperAbstract$text,
                             articleType = paperType,
                             language = "eng",
                             pmcCitationCount = paper_data_results[[i]]$citationStats$numCitations,
                             pmcID = paper_data_results[[i]]$id,
                             doi = ifelse(is.null(paper_data_results[[i]]$primaryPaperLink$url),NA,
                                      paper_data_results[[i]]$primaryPaperLink$url),
                             stringsAsFactors = FALSE)
      
      res<-rbind(res,risResults)
      
      #for some reson, there are duplicated ids
      #that are tricky to pick out
      #so, keep only unique ids
      res<-res %>%
        group_by(PMID)%>%
        sample_n(1)%>%
        ungroup()
       
    }
    
    article_total<- nrow(res)
    page_count<-page_count + 1
    stop_count<-stop_count+1

    if(page_count%%500 == 0){
     Sys.sleep(10)
    }
  }
  
  return(res)
}
