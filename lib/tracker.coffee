fs = require "fs"
util = require "./util"
ucs = util.colorizeString
cFL = util.cutFirstLine
sys = require "sys"

class Tracker
  constructor: (@config) ->
    @_create()
    @created = yes

  ###
  Create new object from params

  @param {Object} params Params object
  @api private
  ###
  _create: (params={}) ->
    @tickets = params.tickets || {}
    @states = params.states || {
      initial: ["todo", "bug", "accept"]
      final: ["done", "fixed", "closed"]}

  ###
  Load tracker file. If file not exists, it will be created with
  default name in work dir

  @param {String} filename Path to tracker file
  @api public
  ###
  load: () ->
    try
      filename = "./" + @config.get "trackerFile"
      @_create JSON.parse fs.readFileSync filename
    catch err
      if "EBADF" == err.code
        @_create()
        if "yes" == @config.get "askBeforeCreate"
          @created = no
          self = @
          util.readOneLine "create new tracker in this folder (yes/no)?", (answer) ->
              if  answer.toLowerCase() in ["yes", "y"]
                self.save()
        else
          @save()
#        fs.writeFileSync filename, JSON.stringify @
      else
        throw err

  ###
  Save tracker file

  @param {String} filename Path to tracker file
  @api public
  ###
  save: () ->
    filename =  "./" + @config.get "trackerFile"
    states = '"states":' + JSON.stringify @states
    tickStr = '"tickets": {\n'
    tickets = []
    for k,v of @tickets
      tickets.push '"' + k + '": ' + JSON.stringify v
    tickStr += tickets.join(", \n") + "\n}"
    data = "{\n#{tickStr},\n#{states}\n}\n"
    fs.writeFileSync filename, data

  ###
  Show project states

  @api public
  ###
  showStates: (which=null) ->
    if null == which
      console.log "Project states:"
      console.log "Initial: #{@states.initial.join ', '} "
      console.log "Final: #{@states.final.join ', '} "
    else if which in ["initial", "final"]
      console.log "#{which} states: #{@states[which].join ', '}"
    else
      console.log 'use "initial" or "final", not #{which}'

  ###
  Update states. Can update "initial" or "final" states

  @param {Array} params List of params. First param must be "initial" of "final",
                        rest params are values for initial or final states
  @param {Object} config Config object
  @api public
  ###
  updateStates: (params, config) ->
    if params[0] in ["initial", "final"]
      @states[params[0]] = params[1..]
      @save()
      console.log "Project #{params[0]} states updated to #{params[1..].join ', '}" if "true" == config.get "verbose"
    else
      console.log "Project states not updated" if "true" == config.get "verbose"

  ###
  Search ticket in tracker

  @param {String} ticketId Ticket id starting numbers
  @param {Object} config Config object
  @return {Array} result Tickets, which have id, strarting from ticketId
  @api private
  ###
  _searchTicket: (ticketId, config) ->
    result = []
    if ticketId.match /^\^.$/
      tickets = @_sortTickets config
      id = parseInt ticketId[1], 36
      result.push tickets[id] if id < tickets.length
    else
      for id, t of @tickets
        if 0 == id.indexOf ticketId
          result.push t
    result

  ###
  Get single ticket by id.
  If ticket id is not unique, method throws exception

  @param {String} ticketId Ticket id starting numbers
  @param {Object} config Config object
  @return {Object} ticket Ticket object
  @api public
  ###
  getSingleTicket: (id) ->
    tickets = @_searchTicket id, @config
    switch tickets.length
      when 1
        return tickets[0]
      when 0
        console.log "Ticket with id, starting from '#{id}' not found"
      else
        console.log "Duplicate tickets with id = #{id} " #(#{sys.inspect tickets})"
    process.exit(-1)


  ###
  Add ticket to tracker

  @param {Object} config Config object
  @param {String} text Text of ticket
  @api public
  ###
  addTicket: (config, text) ->
    d = new Date()
    meta = util.parseText text
    t =
      created: d
      modified: d
      author: config.makeUserDict()
      text: text
      id: util.createId text, config
      comments: []
      log: []
    @tickets[t.id] = t
    @save()
    console.log "You'we added ticket:\n#{text}" if "true" == config.get "verbose"

  ###
  Add unique ticket. Check ticket text for unique before adding

  @param {Object} config Config Object
  @param {String} text Text of ticket
  @api public
  ###
  addUniqueTicket: (config, text) ->
    for id, t of @tickets
      if text.split("\n")[0] == t.text.split("\n")[0]
        console.log "Add duplicate ticket declined" if "true" == config.get "verbose"
        return
    @addTicket config, text

  ###
  Remove ticket from tracker.

  @param {String} id Ticket id  starting numbers
  @param {Object} config Config object
  ###
  removeTicket: (id, config) ->
    t = @getSingleTicket id, config
    delete @tickets[t.id]
    @save()
    console.log "Ticket with #{id.yellow} removed"  if "true" == config.get "verbose"

  removeTickets: (idList, config) ->
    for id in idList
      try
        t = @getSingleTicket id, config
        delete @tickets[t.id]
        console.log "Ticket with #{id.yellow} removed"  if "true" == config.get "verbose"
      catch err
    @save()

  ###
  Change ticket text

  @param {Object} config Config Object
  @param {String} ticketId Ticket id
  @param {Object} text New ticket text
  @api public
  ###
  changeTicket: (config, id, text) ->
    t = @getSingleTicket id, config
    t.author = config.makeUserDict()
    t.text = text
    @updateTicket t

  ###
  Update ticket

  @param {Object} ticket Ticket to update
  @api public
  ###
  updateTicket: (ticket) ->
    @tickets[ticket.id] = ticket
    @save()


  ###
  Comment ticket

  @param {String} ticketId Ticket id
  @param {Object} comment Comment text
  @param {Object} config Config Object
  @api public
  ###
  commentTicket: (id, comment, config) ->
    t = @getSingleTicket id, config
    t.comments.push {
        date: new Date()
        author: config.makeUserDict()
        comment: comment
        id: util.createId comment, config}
      @updateTicket t
    console.log "You add a comment:\n#{comment}"  if "true" == config.get "verbose"

  ###
  Show commnets on ticket

  @param {String} ticketId Ticket id
  @api public
  ###
  showComments: (id) ->
    t = @getSingleTicket id
    @_showTicketComments t, util.getState(t.text, @config) in @states.final

  ###
  Change ticket state

  @param {String} ticketId Ticket id
  @param {String} newState New State value
  @param {Object} config Config object
  @api public
  ###
  changeState: (id, newState, config) ->
    if 0 == newState.indexOf util.statePrefix
      t = @getSingleTicket id, config
      console.log "State of: #{t.text}\nchanged to #{newState}"  if "true" == config.get "verbose"
      t.text = util.replaceState t.text, newState
      t.modified = new Date()
      @updateTicket t


  ###
  Show info on ticket

  @param {Object} config Config object
  @param {String} ticketId Ticket id
  @api public
  ###
  info: (id, config) ->
    @_logOne @getSingleTicket(id, config), null, config

  ###
  Log one ticket full info

  @param {Object} ticket Ticket object
  @param {String} search Search string, default null
  @param {Object} config Config object
  @api private
  ###
  _logOne: (t, search=null, config) ->
    done = util.getState(t.text, config) in @states.final
    console.log ucs "Ticket: #{t.id.yellow}", done, "grey", ""
    console.log ucs "Author: #{t.author.user} <#{t.author.email}>", done, "grey", ""
    console.log ucs "Created: #{t.created}\n", done, "grey", ""
    console.log ucs "Last modified: #{t.modified}", done, "grey", ""
    console.log util.colorizeText t.text, search, done
    _showTicketComments t, done
    console.log  "\n-----------------------------------------"+
      "---------------------------------------\n"

  ###
  Show comments on ticket

  @param {Object} t Ticket object
  @param {Boolean} done Is ticket done
  ###
  _showTicketComments: (t, done) ->
    if 0 < t.comments.length
      console.log ucs "\nComments:\n",  done, "grey", ""
      for c in t.comments
        console.log ucs "#{c.author.user} <#{c.author.email}> :", done, "grey", ""
        console.log ucs c.comment,  done, "grey", ""
    else
      console.log "No comments"


  ###
  Sort tickets

  @param {Object} config Config object.
  @return {Array} tickets Tickets, sorted by asc or desc, depends on config "sortOrder" option
  @api private
  ###
  _sortTickets: (config) ->
    tickets = []
    for id, t of @tickets
      t.state = util.getState t.text, config
      tickets.push t

    [pos, neg] = [1, -1]
    if "desc" == config.get "sortOrder"
      [pos, neg] = [neg, pos]
    states = @states
    tickets.sort (t1, t2) ->
      final1 = t1.state in states.final
      final2 = t2.state in states.final
      if final1 == final2
        if t1.modified == t2.modified
          0
        else if t1.modified  < t2.modified
          pos
        else
          neg
      else if final1
        pos
      else
        neg
    tickets

  ###
  Log + search tickets

  @param {String} search Search string, default null
  @param {Object} config Config object
  @api public
  ###
  log: (search=null, config) ->
    stat = todo:0, done: 0   if null == search
    i = -1
    for t in @_sortTickets config
      i++
      state = util.getState t.text, config
      done = state in @states.final
      if stat         # statistics
        if done
          stat.done++
          continue if "false" == config.get "showDone"
        else
          stat.todo++

      if null == search || 0 <= t.text.indexOf search
        num = if 36 > i then ucs " ^#{i.toString(36)} ", done, "grey", "" else "    "
        switch config.get "log"
          when "tiny"
            console.log "#{num}\t#{util.colorizeText cFL(t.text, 60), null, done}"
          when "long"
            @_logOne t, search
          else                  # short of anything else is default
            comments = if 0 < t.comments.length
                 ucs " [c:#{t.comments.length}]\t", done, "grey", ""
               else
                 "     \t"
            console.log "#{cFL(t.id, 10).yellow}\t" +
               "#{util.colorizeText cFL(t.text, 60), search, done}\t#{num}#{comments}" +
                ucs "#{util.formatDateTime t.modified}\t#{t.author.user}",
                  done, "grey", ""
    if null == search
      total = stat.todo + stat.done
      if 0 < total
        console.log "Tickets: #{stat.done}/#{stat.todo + stat.done}"
      else
        console.log "No tickets yet"
exports.Tracker = Tracker