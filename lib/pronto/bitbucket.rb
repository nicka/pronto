module Pronto
  class Bitbucket
    def initialize(repo)
      @repo = repo
      @config = Config.new
      @comment_cache = {}
      @pull_id_cache = {}
    end

    def pull_comments(sha)
      @comment_cache["#{pull_id}/#{sha}"] ||= begin
        client.pull_comments(slug, pull_id).map do |comment|
          Comment.new(sha, comment.content, comment.filename, comment.line_to)
        end
      end
    end

    def commit_comments(sha)
      @comment_cache[sha.to_s] ||= begin
        client.commit_comments(slug, sha).map do |comment|
          Comment.new(sha, comment.content, comment.filename, comment.line_to)
        end
      end
    end

    def create_commit_comment(comment)
      @config.logger.log("Creating commit comment on #{comment.sha}")
      client.create_commit_comment(slug, comment.sha, comment.body,
                                   comment.path, comment.position)
    end

    def create_pull_comment(comment)
      @config.logger.log("Creating pull request comment on #{pull_id}")
      client.create_pull_comment(slug, pull_id, comment.body,
                                 pull_sha || comment.sha,
                                 comment.path, comment.position)
    end

    private

    def slug
      return @config.bitbucket_slug if @config.bitbucket_slug
      @slug ||= begin
        @repo.remote_urls.map do |url|
          hostname = Regexp.escape(@config.bitbucket_hostname)
          match = /.*#{hostname}(:|\/)(?<slug>.*?)(?:\.git)?\z/.match(url)
          match[:slug] if match
        end.compact.first
      end
    end

    def client
      @client ||= BitbucketClient.new(@config.bitbucket_username,
                                      @config.bitbucket_password)
    end

    def pull_id
      pull ? pull.id.to_i : env_pull_id.to_i
    end

    def env_pull_id
      ENV['PULL_REQUEST_ID']
    end

    def pull_sha
      pull.source['commit']['hash'] if pull
    end

    def pull
      @pull ||= if env_pull_id
                  pull_requests.find { |pr| pr.id.to_i == env_pull_id.to_i }
                elsif @repo.branch
                  pull_requests.find { |pr| pr.branch['name'] == @repo.branch }
                end
    end

    def pull_requests
      @pull_requests ||= client.pull_requests(slug)
    end

    Comment = Struct.new(:sha, :body, :path, :position) do
      def ==(other)
        position == other.position &&
          path == other.path &&
          body == other.body
      end

      def to_s
        "[#{sha}] #{path}:#{position} - #{body}"
      end
    end
  end
end
