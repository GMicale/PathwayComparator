function(input, output, session) {
  
  options(shiny.maxRequestSize=200*1024^2)
  
  last.choice <- reactive(input$geneSel)
  uploaded.files <- reactive(input$uploadedFiles)
  
  shinyInput <- function(FUN, len, id, ...) {
    inputs <- character(len)
    for (i in seq_len(len)) {
      inputs[i] <- as.character(FUN(paste0(id, i), ...))
    }
    inputs
  }
  
  output$listFiles <- DT::renderDT({
   #print(uploaded.files())
    if(length(uploaded.files())==0) {
      tab.data <- data.frame("  "=character()," "=character(),check.names = F)
    } else {
      tab.data <- data.frame("  "=uploaded.files()," "=rep("Remove",length(uploaded.files())),check.names = F)
      tab.data[," "] <- shinyInput(actionButton, length(uploaded.files()),'delete_',label = "",icon=icon("trash"),
                              style = "color: white; background-color: black",
                              onclick = paste0('Shiny.onInputChange( \"delete_button\" , this.id, {priority: \"event\"})'))
    }
    datatable(tab.data, options = list(dom="t",ordering=F, language = list(
        zeroRecords = "No pathway files"),
                                         initComplete = JS(
                                           "function(settings, json) {",
                                           "$(this.api().table().header()).css({'background-color': 'black','color': 'white'});",
                                           "$(this.api().table().body()).css({'background-color': 'black','color': 'white'});",
                                           "}")
                                         ),rownames = F,escape=F)
  })
  
  observeEvent(input$delete_button, {
    selectedRow <- as.numeric(strsplit(input$delete_button, "_")[[1]][2])
    rem.organism <- data.list[[selectedRow]]$organism
    freq.organisms <- table(sapply(data.list,function(el){el$organism}))
    if(freq.organisms[rem.organism]==1) {
      metapathway.list[[rem.organism]] <<- NULL
      pathway.list[[rem.organism]] <<- NULL
    }
    data.list[[selectedRow]] <<- NULL
    #if(length(data.list)>0) {}
    updateSelectInput(session,"uploadedFiles",choices=input$uploadedFiles[-selectedRow],selected=input$uploadedFiles[-selectedRow])
    if(length(data.list)==1) {
      updateActionButton(session,"compare",label="Show",disabled=F)
    } else if(length(data.list)>1) {
      updateActionButton(session,"compare",label="Compare",disabled=F)
    } else {
      updateActionButton(session,"compare",label="Show",disabled=T)
    }
  })
  
  observeEvent(input$hiddenUpload,{
    file.list <- input$hiddenUpload
    req(file.list)
    print(file.list)
    dataname.list <- c()
    for(i in 1:nrow(file.list)) {
      file <- file.list[i,]
      dataname <- strsplit(file$name,"\\.")[[1]][1]
      file.data <- read.phensim.file(file$datapath)
      if(dataname %in% names(data.list)) {
        dataname <- paste0(dataname,"_",(length(input$uploadedFiles)+1))
      }
      data.list[[dataname]] <<- file.data
      organism <- as.character(file.data$organism)
      if(!organism %in% names(metapathway.list)) {
        metapathway.list[[organism]] <<- readRDS(paste0("Data/Metapathways/",organism,".rds"))
        pathway.list[[organism]] <<- readRDS(paste0("Data/Pathways/",organism,".rds"))
      }
      dataname.list <- c(dataname.list,dataname)
    }
    updateSelectInput(session,"uploadedFiles",choices=c(input$uploadedFiles,dataname.list),selected=c(input$uploadedFiles,dataname.list))
    if(length(data.list)==1) {
      updateActionButton(session,"compare",label="Show",disabled=F)
    } else if(length(data.list)>1) {
      updateActionButton(session,"compare",label="Compare",disabled=F)
    } else {
      updateActionButton(session,"compare",label="Show",disabled=T)
    }
  })
  
  observeEvent(input$compare, {
    data.list <- data.list[order(sapply(data.list, function(el) el$organism))]
    list.organism <- as.character(sapply(data.list,function(el){el$organism}))
    #print(list.organism)
    if(length(list.organism)>1){
      org.pairs <- apply(t(combn(sort(list.organism),2)),1,function(row){paste0(row,collapse="-")})
      for(pair in org.pairs) {
        ortho.list[[pair]] <<- readRDS(paste0("Data/Orthologs/",pair,".rds"))
      } 
    } else {
      pair <- paste0(list.organism,"-",list.organism)
      ortho.list[[pair]] <<- readRDS(paste0("Data/Orthologs/",pair,".rds"))
    }
    list.pathways <- sapply(list.organism,function(org){unique(pathway.list[[org]]$pathwayName)})
    if(is.list(list.pathways)) {
      common.pathways <- Reduce(intersect,list.pathways)
    } else {
      common.pathways <- list.pathways
    }
    updateSelectizeInput(session,"pathwaySel",choices=sort(common.pathways), server=TRUE)
    max.opt <- 3
    if(length(data.list)==2)
      max.opt <- 2
    updatePickerInput(session,"networkSel",choices=names(data.list),selected = names(data.list)[1:max.opt])
  })
  
  observeEvent(input$pathwaySel,{
    if(input$pathwaySel!="" && !is.null(input$networkSel)) {
      updated.list <- get.list.selectable.nodes(input$pathwaySel,input$networkSel,input$hideElements)
      updateSelectizeInput(session,"geneSel",choices=updated.list, selected="All", server=TRUE)
    } else {
      updateSelectizeInput(session,"geneSel",choices=NULL,server=T)
    }
  }, ignoreNULL = FALSE)
  
  observeEvent({
    input$networkSel
    input$hideElements
  },{
    if(input$pathwaySel!="" && !is.null(input$networkSel)) {
      updated.list <- get.list.selectable.nodes(input$pathwaySel,input$networkSel,input$hideElements)
      choice.info <- strsplit(last.choice(),"\n")[[1]]
      if(last.choice() %in% updated.list[[choice.info[2]]]) {
        updateSelectizeInput(session, "geneSel", selected=last.choice(), choices=updated.list, server=TRUE)
      } else{
        updateSelectizeInput(session, "geneSel", selected="All", choices=updated.list, server=TRUE)
      }
    } else {
      updateSelectizeInput(session,"geneSel",choices=NULL,server=T)
    }
  }, ignoreNULL = F)
  
  output$plotPathway <- renderVisNetwork({
    if(input$pathwaySel!="" && input$geneSel!="" && !is.null(input$networkSel)){
      multilayer.net <- build.pathway.net(data.list,metapathway.list,pathway.list,ortho.list,
                            input$networkSel,input$pathwaySel,input$geneSel,input$hideElements)
      pathway.plot <- plot.pathway(multilayer.net$nodes,multilayer.net$edges,input$pathwaySel)
      pathway.plot
    }
  })
  
}