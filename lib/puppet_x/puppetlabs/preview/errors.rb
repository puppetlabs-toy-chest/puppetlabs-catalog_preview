module PuppetX::Puppetlabs::Preview

  class PreviewError < StandardError
  end

  class GeneralError < PreviewError
  end

  class BaselineCompileError < PreviewError
  end

  class PreviewCompileError < PreviewError
  end

  class QueryError < PreviewError
  end
end
