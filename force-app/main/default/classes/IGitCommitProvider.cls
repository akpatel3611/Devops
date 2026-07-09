/**
 * Provider interface for Git commit operations.
 * Defines the contract that version control provider implementations must satisfy.
 */
public interface IGitCommitProvider {
    GitCommitResult executeCommit(GitCommitContext context, String commitMessage);
}