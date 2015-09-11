
class TokenAuthor
  attr_accessor :surname

  def initials
    @initials ||= []
  end

  def add_initial(initial)
    initials.push initial
    self
  end

  def full_name
    [*initials, surname].join('').strip
  end

end


class TokenCompany
  attr_accessor :type

  def name_words
    @name_words ||= []
  end

  def add_name_word(word)
    name_words.push word
    self
  end

  def full_name
    [type, ' ', *name_words].join('').strip
  end

end


class TokenParser

  attr_accessor :subject_tokens

  def initialize(subject_tokens)
    @subject_tokens = subject_tokens
  end

  def result
    @result ||= Hash.new { |h, k| h[k] = Set.new }
  end

  def new_author
    result[:authors].add(@author = TokenAuthor.new)
    @author
  end

  def current_author
    @author ||= new_author
  end

  def reset_author
    @author = nil
  end

  def current_company
    @company
  end

  def new_company
    result[:authors].add(@company = TokenCompany.new)
    @company
  end

  def reset_company
    @company = nil
  end

  def parse
    subject_tokens.each do |token|
      if current_company
        case token.type
        when :duration
          reset_company
        else
          current_company.add_name_word token.matched
        end
      else
        case token.type
        when :surname
          current_author.surname = token.value
        when :initial
          current_author.add_initial token.value
        when :occupation, :position, :citizenship, :location
          reset_author
          result[token.type] << token.value
        when :company_type
          new_company.type = token.value
        else
          reset_author
        end
      end
    end
    result
  end

end
