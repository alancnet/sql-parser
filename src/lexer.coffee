{Observable} = require 'rxjs'
class Lexer
  constructor: (stream, opts={}) ->
    @observable = Observable.create((observer) =>
      @observer = observer
      @sql = ''
      @preserveWhitespace = opts.preserveWhitespace || false
      @tokens = []
      @currentLine = 1
      @currentOffset = 0
      stream.subscribe(
        (data) =>
          @sql += data
          i = 0
          while (@chunk = @sql.slice(i)).length
            bytesConsumed =  @keywordToken() or
                             @starToken() or
                             @booleanToken() or
                             @functionToken() or
                             @windowExtension() or
                             @sortOrderToken() or
                             @seperatorToken() or
                             @operatorToken() or
                             @mathToken() or
                             @dotToken() or
                             @semicolonToken() or
                             @conditionalToken() or
                             @betweenToken() or
                             @subSelectOpToken() or
                             @subSelectUnaryOpToken() or
                             @numberToken() or
                             @stringToken() or
                             @parameterToken() or
                             @parensToken() or
                             @whitespaceToken() or
                             @literalToken()
            if bytesConsumed < 1
              break
            i += bytesConsumed
            @currentOffset += bytesConsumed
          @sql = @chunk

        (err) =>
          @observer.error(err)
        () =>
          @token('EOF', '')
          @observer.complete()
      )
      # @postProcess()
    )

  postProcess: ->
    for token, i in @tokens
      if token[0] is 'STAR'
        next_token = @tokens[i+1]
        unless next_token[0] is 'SEPARATOR' or next_token[0] is 'FROM'
          token[0] = 'MATH_MULTI'

  token: (name, value) ->
    @observer.next([name, value, @currentLine, @currentOffset])
    @tokens.push([name, value, @currentLine, @currentOffset])

  tokenizeFromStringRegex: (name, regex, part=0, lengthPart=part, output=true) ->
    return 0 unless match = regex.exec(@chunk)
    partMatch = match[part].replace(/''/g, "'")
    @token(name, partMatch) if output
    return match[lengthPart].length

  tokenizeFromRegex: (name, regex, part=0, lengthPart=part, output=true) ->
    return 0 unless match = regex.exec(@chunk)
    partMatch = match[part]
    @token(name, partMatch) if output
    return match[lengthPart].length

  tokenizeFromWord: (name, word=name) ->
    word = @regexEscape(word)
    matcher = if (/^\w+$/).test(word)
      new RegExp("^(#{word})\\b",'ig')
    else
      new RegExp("^(#{word})",'ig')
    match = matcher.exec(@chunk)
    return 0 unless match
    @token(name, match[1])
    return match[1].length

  tokenizeFromList: (name, list) ->
    ret = 0
    for entry in list
      ret = @tokenizeFromWord(name, entry)
      break if ret > 0
    ret

  keywordToken: ->
    @tokenizeFromWord('SELECT') or
    @tokenizeFromWord('INSERT') or
    @tokenizeFromWord('INTO') or
    @tokenizeFromWord('DEFAULT') or
    @tokenizeFromWord('VALUES') or
    @tokenizeFromWord('DISTINCT') or
    @tokenizeFromWord('FROM') or
    @tokenizeFromWord('WHERE') or
    @tokenizeFromWord('GROUP') or
    @tokenizeFromWord('ORDER') or
    @tokenizeFromWord('BY') or
    @tokenizeFromWord('HAVING') or
    @tokenizeFromWord('LIMIT') or
    @tokenizeFromWord('JOIN') or
    @tokenizeFromWord('LEFT') or
    @tokenizeFromWord('RIGHT') or
    @tokenizeFromWord('INNER') or
    @tokenizeFromWord('OUTER') or
    @tokenizeFromWord('ON') or
    @tokenizeFromWord('AS') or
    @tokenizeFromWord('CASE') or
    @tokenizeFromWord('WHEN') or
    @tokenizeFromWord('THEN') or
    @tokenizeFromWord('ELSE') or
    @tokenizeFromWord('END') or
    @tokenizeFromWord('UNION') or
    @tokenizeFromWord('ALL') or
    @tokenizeFromWord('LIMIT') or
    @tokenizeFromWord('OFFSET') or
    @tokenizeFromWord('FETCH') or
    @tokenizeFromWord('ROW') or
    @tokenizeFromWord('ROWS') or
    @tokenizeFromWord('ONLY') or
    @tokenizeFromWord('NEXT') or
    @tokenizeFromWord('FIRST')

  dotToken: -> @tokenizeFromWord('DOT', '.')
  semicolonToken:   -> @tokenizeFromWord('SEMICOLON', ';')
  operatorToken:    -> @tokenizeFromList('OPERATOR', SQL_OPERATORS)
  mathToken:        ->
    @tokenizeFromList('MATH', MATH) or
    @tokenizeFromList('MATH_MULTI', MATH_MULTI)
  conditionalToken: -> @tokenizeFromList('CONDITIONAL', SQL_CONDITIONALS)
  betweenToken:     -> @tokenizeFromList('BETWEEN', SQL_BETWEENS)
  subSelectOpToken: -> @tokenizeFromList('SUB_SELECT_OP', SUB_SELECT_OP)
  subSelectUnaryOpToken: -> @tokenizeFromList('SUB_SELECT_UNARY_OP', SUB_SELECT_UNARY_OP)
  functionToken:    -> @tokenizeFromList('FUNCTION', SQL_FUNCTIONS)
  sortOrderToken:   -> @tokenizeFromList('DIRECTION', SQL_SORT_ORDERS)
  booleanToken:     -> @tokenizeFromList('BOOLEAN', BOOLEAN)

  starToken:        -> @tokenizeFromRegex('STAR', STAR)
  seperatorToken:   -> @tokenizeFromRegex('SEPARATOR', SEPARATOR)
  literalToken:     -> @tokenizeFromRegex('LITERAL', LITERAL, 1, 0)
  numberToken:      -> @tokenizeFromRegex('NUMBER', NUMBER)
  parameterToken:   -> @tokenizeFromRegex('PARAMETER', PARAMETER, 1, 0)
  stringToken:      -> @tokenizeString()
    # @tokenizeFromStringRegex('STRING', STRING, 1, 0) ||
    # @tokenizeFromRegex('DBLSTRING', DBLSTRING, 1, 0)

  tokenizeString: ->
    i = 0
    eof = () => i >= @chunk.length
    peek = () => @chunk.charAt(i)
    pop = () => @chunk.charAt(i++)
    if (peek() == '"' or peek() == "'")
      ret = []
      q = pop()
      while !eof()
        c = pop()
        if c == q # Closing quote?
          if peek() == q # No, escaped quote.
            ret.push(pop())
          else # Yes, closing quote.
            @token('STRING', ret.join(''))
            return i
        else if c == '\\' # Escape character
          ret.push(pop()) # Just emit the character
        else
          ret.push(c) # Other character. Just emit.
    return 0

  parensToken: ->
    @tokenizeFromRegex('LEFT_PAREN', /^\(/,) or
    @tokenizeFromRegex('RIGHT_PAREN', /^\)/,)

  windowExtension: ->
    match = (/^\.(win):(length|time)/i).exec(@chunk)
    return 0 unless match
    @token('WINDOW', match[1])
    @token('WINDOW_FUNCTION', match[2])
    match[0].length

  whitespaceToken: ->
    return 0 unless match = WHITESPACE.exec(@chunk)
    partMatch = match[0]
    @token('WHITESPACE', partMatch) if @preserveWhitespace
    newlines = partMatch.match(/\n/g, '')
    @currentLine += newlines?.length || 0
    return partMatch.length

  regexEscape: (str) ->
    str.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&")

  SQL_FUNCTIONS       = ['AVG', 'COUNT', 'MIN', 'MAX', 'SUM']
  SQL_SORT_ORDERS     = ['ASC', 'DESC']
  SQL_OPERATORS       = ['=', '!=', '>=', '>', '<=', '<>', '<', 'LIKE', 'NOT LIKE', 'ILIKE', 'NOT ILIKE', 'IS', 'IS NOT', 'REGEXP', 'NOT REGEXP']
  SUB_SELECT_OP       = ['IN', 'NOT IN', 'ANY', 'ALL', 'SOME']
  SUB_SELECT_UNARY_OP = ['EXISTS']
  SQL_CONDITIONALS    = ['AND', 'OR']
  SQL_BETWEENS        = ['BETWEEN', 'NOT BETWEEN']
  BOOLEAN             = ['TRUE', 'FALSE', 'NULL']
  MATH                = ['+', '-', '||', '&&']
  MATH_MULTI          = ['/', '*']
  STAR                = /^\*/
  SEPARATOR           = /^,/
  WHITESPACE          = /^[ \n\r\t]+/
  LITERAL             = /^`?([a-z_][a-z0-9_]{0,}(\:(number|float|string|date|boolean))?)`?/i
  PARAMETER           = /^\$([a-z0-9_]+(\:(number|float|string|date|boolean))?)/
  NUMBER              = /^[0-9]+(\.[0-9]+)?/
  STRING              = /^'([^\\']*(?:\\.[^\\']*)*)'/
  DBLSTRING           = /^"([^\\"]*(?:\\.[^\\"]*)*)"/



exports.tokenize = (stream, opts) -> (new Lexer(stream, opts)).observable
