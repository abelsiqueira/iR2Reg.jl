# NormTVp and ShiftedNormTVp Implementation

"""
    NormTVp(λ::Real or AbstractArray, p::Real)

Represents the Total Variation (TV) norm with parameter `p` and scaling factor `λ`.
"""
struct NormTVp{T1,T2}
    λ::T1
    p::T2

    function NormTVp(λ::T1, p::T2) where {T1,T2}
        if λ isa Real
            λ < 0 && error("λ must be nonnegative")
        elseif λ isa AbstractArray
            eltype(λ) <: Real || error("Elements of λ must be real")
            any(λ .< 0) && error("All elements of λ must be nonnegative")
        else
            error("λ must be a real scalar or array")
        end

        p >= 1 || error("p must be greater than or equal to one")
        new{T1,T2}(λ, p)
    end
end

"""
    TVp_norm(x::AbstractArray, p::Real)

Computes the TVp norm of vector `x` with parameter `p`.
"""
function TVp_norm(x::AbstractArray, p::Real)
    n = length(x)
    tvp_sum = 0.0
    for i = 1:(n-1)
        tvp_sum += abs(x[i+1] - x[i])^p
    end
    return tvp_sum^(1 / p)
end

# Allows NormTVp objects to be called as functions
function (h::NormTVp)(x::AbstractArray)
    return h.λ * TVp_norm(x, h.p)
end

"""
    ShiftedNormTVp

A mutable struct representing a shifted NormTVp function.
"""
mutable struct ShiftedNormTVp{
    R<:Real,
    T<:Real,
    V0<:AbstractVector{R},
    V1<:AbstractVector{R},
    V2<:AbstractVector{R},
}
    h::NormTVp{R,T}
    xk::V0
    sj::V1
    sol::V2
    shifted_twice::Bool
    xsy::V2

    function ShiftedNormTVp(
        h::NormTVp{R,T},
        xk::AbstractVector{R},
        sj::AbstractVector{R},
        shifted_twice::Bool,
    ) where {R<:Real,T<:Real}
        sol = similar(xk)
        xsy = similar(xk)
        new{R,T,typeof(xk),typeof(sj),typeof(sol)}(h, xk, sj, sol, shifted_twice, xsy)
    end
end

"""
    shifted(h::NormTVp, xk::AbstractVector)

Creates a ShiftedNormTVp object with initial shift `xk`.
"""
shifted(h::NormTVp{R,T}, xk::AbstractVector{R}) where {R<:Real,T<:Real} =
    ShiftedNormTVp(h, xk, zero(xk), false)

"""
    shifted(ψ::ShiftedNormTVp, sj::AbstractVector)

Creates a ShiftedNormTVp object by adding a second shift `sj`.
"""
shifted(
    ψ::ShiftedNormTVp{R,T,V0,V1,V2},
    sj::AbstractVector{R},
) where {
    R<:Real,
    T<:Real,
    V0<:AbstractVector{R},
    V1<:AbstractVector{R},
    V2<:AbstractVector{R},
} = ShiftedNormTVp(ψ.h, ψ.xk, sj, true)

# Functions to get the name, expression, and parameters of the function
fun_name(ψ::ShiftedNormTVp) = "shifted TVp norm"
fun_expr(ψ::ShiftedNormTVp) = "t ↦ λ * TVp(xk + sj + t)"
fun_params(ψ::ShiftedNormTVp) = "xk = $(ψ.xk)\n" * " "^14 * "sj = $(ψ.sj)"

"""
    shift!(ψ::ShiftedNormTVp, shift::AbstractVector)

Updates the shift of a ShiftedNormTVp object.
"""
function shift!(ψ::ShiftedNormTVp, shift::AbstractVector{R}) where {R<:Real}
    if ψ.shifted_twice
        ψ.sj .= shift
    else
        ψ.xk .= shift
    end
    return ψ
end

# Allows ShiftedNormTVp objects to be called as functions
function (ψ::ShiftedNormTVp)(y::AbstractVector)
    @. ψ.xsy = ψ.xk + ψ.sj + y
    return ψ.h(ψ.xsy)
end

"""
    prox!(y::AbstractArray, ψ::ShiftedNormTVp, q::AbstractArray, σ::Real)

Computes the proximity operator of a shifted TVp object.

Inputs:
    - `y`: Array in which to store the result.
    - `ψ`: ShiftedNormTVp object.
    - `q`: Vector to which the proximity operator is applied.
    - `σ`: Scaling factor.
    - `objGap`: Desired quality of the solution in terms of duality gap (default `1e-5`).

Although `objGap` can be specified, the TVp proximity operator uses a fixed objective gap of `1e-5` as defined in the C++ code. A warning will be emitted the first time this function is called.

"""
function prox!(y::AbstractArray, ψ::ShiftedNormTVp, q::AbstractArray, σ::Real; kwargs...)
    n = length(y)
    ws = ProxTV.newWorkspace(n)

    # Allocate info array (based on C++ code)
    info = zeros(Float64, 3)

    # Compute y_shifted = xk + sj + q
    y_shifted = ψ.xk .+ ψ.sj .+ q

    # Adjust lambda to account for σ (multiply λ by σ)
    lambda_scaled = ψ.h.λ * σ

    # Allocate the x vector to store the intermediate solution
    x = similar(y)

    # Call the TV function from ProxTV package
    ProxTV.TV(y_shifted, lambda_scaled, x, info, Int32(n), ψ.h.p, ws)

    # Compute s = x - xk - sj
    s = x .- ψ.xk .- ψ.sj

    # Store the result in y
    y .= s

    return y
end
