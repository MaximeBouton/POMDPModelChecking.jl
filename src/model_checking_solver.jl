@with_kw mutable struct ModelCheckingSolver <: Solver 
    property::SpotFormula = ltl"true" 
    solver::Solver = ValueIterationSolver() # can use any solver that returns a value function :o
    verbose::Bool = false
end

mutable struct ModelCheckingPolicy{P <: Policy, M <:Union{ProductMDP, ProductPOMDP}, Q} <: Policy
    policy::P
    problem::M
    memory::Q
end

# NOTE: the returned value function will be 0. at the accepting states instead of 1, this is overriden by the implementation 
# of POMDPs.value below but only for MDPs. A solution would be to add a sink state
function POMDPs.solve(solver::ModelCheckingSolver, problem::M) where M<:Union{MDP,POMDP}
    verbose = solver.verbose
    # parse formula first 
    automata = DeterministicRabinAutomata(solver.property)
    pmdp = nothing
    sink_state = ProductState(first(states(problem)), -1)
    if isa(problem, POMDP)
        pmdp = ProductPOMDP(problem, automata, sink_state)
    else
        pmdp = ProductMDP(problem, automata, sink_state) # build product mdp x automata
    end
    if isempty(pmdp.accepting_states)
        mec_time = @elapsed begin
            accepting_states!(pmdp, verbose=verbose) # compute the maximal end components via a graph analysis
            verbose ? println("Found ", length(pmdp.accepting_states), " accepting states") : nothing
        end
    end
    println("MEC comp time: ", mec_time)
    policy = solve(solver.solver, pmdp) # solve using your favorite method
    return ModelCheckingPolicy(policy, pmdp, get_init_state_number(automata))
end

# For MDPs 

function POMDPs.action(policy::ModelCheckingPolicy{P, M}, s) where {P <: Policy, M <: ProductMDP}
    a = action(policy.policy, ProductState(s, policy.memory))
    update_memory!(policy, s, a)
    return a
end

function POMDPs.action(policy::ModelCheckingPolicy{P, M}, s::ProductState{S, Q}) where {P <: Policy, M <: ProductMDP, S, Q}
    return action(policy.policy, s)
end

function POMDPs.value(policy::ModelCheckingPolicy{P, M}, s) where {P <: Policy, M <: ProductMDP}
    return value(policy, ProductState(s, policy.memory))
end

function POMDPs.value(policy::ModelCheckingPolicy{P, M}, s::ProductState{S, Q}) where {P <: Policy, M <: ProductMDP, S, Q}
    if s ∈ policy.problem.accepting_states  # see comment in POMDPs.solve
        return 1.0 
    else
        return value(policy.policy, s)
    end
end

function POMDPPolicies.actionvalues(policy::ModelCheckingPolicy{P, M}, s) where {P <: Policy, M <: ProductMDP}
    return actionvalues(policy, ProductState(s, policy.memory))
end

function POMDPPolicies.actionvalues(policy::ModelCheckingPolicy{P, M}, s::ProductState{S, Q}) where {P <: Policy, M <: ProductMDP, S, Q}
    if s ∈ policy.problem.accepting_states
        return ones(n_actions(policy.problem))
    else
        return actionvalues(policy.policy, s)
    end
end

function reset_memory!(policy::ModelCheckingPolicy)
    policy.memory = get_init_state_number(policy.problem.automata)
end

function update_memory!(policy::ModelCheckingPolicy, s, a)
    l = labels(policy.problem.problem, s, a)
    qp = nextstate(policy.problem.automata, policy.memory, l)
    # println("current automata state: " , policy.memory, "  next state " , qp)
    if qp != nothing 
        policy.memory = qp
    end
end

# For POMDPs

POMDPs.action(policy::ModelCheckingPolicy{P, M}, b) where {P <: Policy, M <: ProductPOMDP} = action(policy.policy, b)
POMDPs.value(policy::ModelCheckingPolicy{P, M}, b) where {P <: Policy, M <: ProductPOMDP} = value(policy.policy, b)
POMDPPolicies.actionvalues(policy::ModelCheckingPolicy{P, M}, b) where {P <: Policy, M <: ProductPOMDP} = actionvalues(policy.policy, b)