module decentralized_insurance::insurance {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self};
    use sui::object::{Self, UID, ID};
    use sui::transfer::{Self};
    use sui::event;

    use std::vector;

    // Errors Definitions
    const ERROR_CLAIM_NOT_VERIFIED: u64 = 2;
    const ERROR_CLAIMANT_CANNOT_VERIFY: u64 = 4;
    const ERROR_VERIFIER_ALREADY_VERIFIED: u64 = 5;
    const ERROR_CLAIM_CONDITIONS_NOT_MET: u64 = 6; 
    const ERROR_POLICY_IS_ACTIVE: u64 = 7;
    const ERROR_INSUFFICIENT_POOL_BALANCE: u64 = 8;
    const ERROR_AMOUNT_IS_LESS_THAN_THE_PREMIUM: u64 = 9;
    
    // Struct representing an insurance policy
    struct Policy has key, store {
        id: UID,
        owner: address,
        premium: u64,
        coverage: u64,
        conditions: vector<u8>,
        is_active: bool,
    }
    
    // Struct representing a claim
    struct Claim has key, store {
        id: UID,
        policy_id: u64,
        claimant: address,
        verifiers: vector<address>,
        amount: u64,
        is_verified: bool,
        is_paid: bool,
    }

    // Struct representing a community pool
    struct CommunityPool has key, store {
        id: UID,
        balance: u64,
        stakers: vector<address>,
        // rewards: u64,
    }
    
    // Events
    struct PolicyCreated has copy, drop { owner: address, premium: u64, coverage: u64, conditions: vector<u8>}

    struct ClaimCreated has copy, drop { id: ID, policy_id: u64 }

    struct ClaimPaid has copy, drop { id: ID, amount: u64 }
    
    // Create a new insurance policy
    public fun create_policy(owner: address, premium: u64, coverage: u64, conditions: vector<u8>, ctx: &mut TxContext): Policy {
        let policy_id = object::new(ctx);
        let policy = Policy {
            id: policy_id,
            owner,
            premium,
            coverage,
            conditions,
            is_active: true,
        };
        event::emit(PolicyCreated { 
            owner,
            premium,
            coverage,
            conditions,
        });
        policy
    }
    
    // Pay premium for an insurance policy
    public fun pay_premium(
        policy: &mut Policy, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext,
        ) {
        assert!(policy.is_active, ERROR_POLICY_IS_ACTIVE);
        assert!(coin::value(&payment) >= policy.premium, ERROR_AMOUNT_IS_LESS_THAN_THE_PREMIUM);
        let payer = tx_context::sender(ctx);
        policy.owner = payer;
        policy.is_active = true;
        
        transfer::public_transfer(payment, policy.owner);
        
        event::emit(PolicyCreated { 
            owner: payer,
            premium: policy.premium,
            coverage: policy.coverage,
            conditions: policy.conditions,
        });
    }
    
    // Create a new claim
    public fun create_claim(policy_id: u64, claimant: address, amount: u64, ctx: &mut TxContext): Claim {
        let claim_id = object::new(ctx);
        let claim = Claim {
            id: claim_id,
            policy_id,
            claimant,
            verifiers: vector::empty<address>(),
            amount,
            is_verified: false,
            is_paid: false,
        };
        // event::emit(ClaimCreated { id: claim_id, policy_id });
        
        
        claim
    }
    
    // Verify a claim
    public fun verify_claim(claim: &mut Claim, verifier: address) {
        // Ensure the verifier is not the claimant
        assert!(verifier != claim.claimant, ERROR_CLAIMANT_CANNOT_VERIFY);
        
        // Ensure the verifier hasn't already verified this claim
        assert!(!vector::contains(&claim.verifiers, &verifier), ERROR_VERIFIER_ALREADY_VERIFIED);
        
        // Verify conditions for the claim
        let all_conditions_met = true; 
        
        assert!(all_conditions_met, ERROR_CLAIM_CONDITIONS_NOT_MET);
        // Add verifier to the list of verifiers
        vector::push_back(&mut claim.verifiers, verifier);
        
        // If sufficient verifiers have verified, mark the claim as verified
        if (vector::length(&claim.verifiers) > 1) {  // Example: require 2 verifiers
            claim.is_verified = true;
        };
    }
    
    // Pay a verified claim
    public fun pay_claim(claim: &mut Claim, pool: &mut CommunityPool, payment: Coin<SUI>, ctx: &mut TxContext) {
        assert!(claim.is_verified, ERROR_CLAIM_NOT_VERIFIED);
        assert!(pool.balance >= claim.amount, ERROR_INSUFFICIENT_POOL_BALANCE);
        claim.is_paid = true;
        transfer::public_transfer(payment, claim.claimant);
    }
    
    // // Create a community pool
    // public fun create_community_pool(ctx: &mut TxContext): CommunityPool {
    //     let pool_id = object::newcoin: Coin<SUI>(ctx);
    //     CommunityPool {
    //         id: pool_id,
    //         balance: 0,
    //         stakers: vector::empty<address>(),
    //         rewards: INITIAL_REWARD,
    //     }
    // }
    
    // Stake tokens in a community pool
    public fun stake(pool: &mut CommunityPool, staker: address, amount: u64, ctx: &mut TxContext) {
        // pool.balance += amount;
        vector::push_back(&mut pool.stakers, staker);
    }

//     // Reward stakers based on pool performance
//     public fun reward_stakers(pool: &mut CommunityPool, ctx: &mut TxContext) {
//         let num_stakers = vector::length(&pool.stakers);
//         let reward_per_staker = pool.rewards / num_stakers;
//         for staker in &pool.stakers {
//             transfer::public_transfer(coin::new(reward_per_staker, ctx), *staker);
//         }
//     }
}
