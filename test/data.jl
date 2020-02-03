module TestData

using Test
using DataFrames
import TypedTables
using CategoricalArrays
import Tables
using ScientificTypes

using Random
import Random.seed!
seed!(1234)

import MLJBase
import MLJBase: decoder, int, classes, partition, unpack, selectcols, matrix,
    CategoricalElement, selectrows, select, table, nrows, restrict,
    corestrict, complement

@testset "partition" begin
    train, test = partition(1:100, 0.9)
    @test collect(train) == collect(1:90)
    @test collect(test) == collect(91:100)
    seed!(1234)
    train, test = partition(1:100, 0.9, shuffle=true)
    @test length(train) == 90
    @test length(test) == 10
    @test train[1:8] == [40, 88, 59, 94, 79, 7, 67, 62]

    train, test = partition(1:100, 0.9, rng=1)
    seed!(1)
    train2, test2 = partition(1:100, 0.9, shuffle=true)
    @test train2 == train
    @test test2 == test

    train3, test3 = partition(1:100, 0.9, rng=Random.MersenneTwister(1))
    @test train3 == train
    @test test3 == test

    train, test = partition(1:100, 0.9, shuffle=false, rng=1)
    @test collect(train) == collect(1:90)
    @test collect(test) == collect(91:100)

    # with stratification
    y = ones(Int, 1000)
    y[end-100:end] .= 0; # 90%

    train, test = partition(eachindex(y), 0.8, stratify=y, rng=34)
    @test isapprox(sum(y[train])/length(train), 0.9, rtol=1e-2)
    @test isapprox(sum(y[test])/length(test), 0.9, rtol=1e-2)

    s1, s2, s3 = partition(eachindex(y), 0.3, 0.6, stratify=y, rng=345)
    @test isapprox(sum(y[s1])/length(s1), 0.9, rtol=1e-2)
    @test isapprox(sum(y[s2])/length(s2), 0.9, rtol=1e-2)
    @test isapprox(sum(y[s3])/length(s3), 0.9, rtol=1e-2)

    y = ones(Int, 1000)
    y[end-500:end-200] .= 2
    y[end-200+1:end] .= 3
    p1 = sum(y .== 1) / length(y) # 0.5
    p2 = sum(y .== 2) / length(y) # 0.3
    p3 = sum(y .== 3) / length(y) # 0.2

    s1, s2, s3 = partition(eachindex(y), 0.3, 0.6, stratify=y, rng=111)
    # overkill test...
    for s in (s1, s2, s3)
        for (i, p) in enumerate((p1, p2, p3))
            @test isapprox(sum(y[s] .== i)/length(s), p, rtol=1e-2)
        end
    end

    # it should work with missing values though maybe not recommended...
    y = ones(Union{Missing,Int}, 1000)
    y[end-600:end-550] .= missing
    y[end-500:end-200] .= 2
    y[end-200+1:end] .= 3
    p1 = sum(skipmissing(y) .== 1) / length(y) # 0.45
    p2 = sum(skipmissing(y) .== 2) / length(y) # 0.3
    p3 = sum(skipmissing(y) .== 3) / length(y) # 0.2
    pm = sum(ismissing.(y)) / length(y)        # 0.05

    s1, s2 = partition(eachindex(y), 0.7, stratify=y, rng=11)
    for s in (s1, s2)
        for (i, p) in enumerate((p1, p2, p3))
            @test isapprox(sum(y[s] .=== i)/length(s), p, rtol=1e-2)
        end
        @test isapprox(sum(ismissing.(y[s]))/length(s), pm, rtol=1e-1)
    end

    # test ordering is preserved if no shuffle
    s1, s2 = partition(eachindex(y), 0.7, stratify=y)
    @test issorted(s1)
    @test issorted(s2)

    s1, s2 = partition(eachindex(y), 0.7, stratify=y, shuffle=true)
    @test !issorted(s1)
    @test !issorted(s2)
end

@testset "unpack" begin
    channing = TypedTables.Table(
        Sex = categorical(["Female", "Male", "Female"]),
        Entry = Int32[965, 988, 850],
        Exit = Int32[1088, 1045, 940],
        Time = Int32[123, 57, 90],
        Cens = Int32[0, 0, 1],
        weights = [1,2,5])

    w, y, X =  unpack(channing,
                  ==(:weights),
                  ==(:Exit),
                  x -> x != :Time;
                  :Exit=>Continuous,
                  :Entry=>Continuous,
                  :Cens=>Multiclass)

    @test w == selectcols(channing, :weights)
    @test y == selectcols(channing, :Exit)
    @test X == selectcols(channing, [:Sex, :Entry, :Cens])
    @test scitype_union(y) <: Continuous
    @test scitype_union(selectcols(X, :Cens)) <: Multiclass


    w, y, X =  unpack(channing,
                      ==(:weights),
                      ==(:Exit),
                      x -> x != :Time;
                      wrap_singles=true,
                      :Exit=>Continuous,
                      :Entry=>Continuous,
                      :Cens=>Multiclass)

    @test selectcols(w, 1)  == selectcols(channing, :weights)
    @test selectcols(y, 1)  == selectcols(channing, :Exit)
    @test X == selectcols(channing, [:Sex, :Entry, :Cens])

    @test_throws(Exception, unpack(channing,
                                   ==(:weights),
                                   ==(:Exit),
                                   ==(:weights),
                                   x -> x != :Time;
                                   :Exit=>Continuous,
                                   :Entry=>Continuous,
                                   :Cens=>Multiclass))

end

@testset "restrict and corestrict" begin
    f = ([1], [2, 3], [4, 5, 6, 7], [8, 9, 10])
    @test complement(f, 1) == [2, 3, 4, 5, 6, 7, 8, 9, 10]
    @test complement(f, 2) == [1, 4, 5, 6, 7, 8, 9, 10]
    @test complement(f, 3) == [1, 2, 3, 8, 9, 10]
    @test complement(f, 4) == [1, 2, 3, 4, 5, 6, 7]

    X = 10:10:100
    @test restrict(X, f, 3) == 40:10:70
    @test corestrict(X, f, 3) == [10, 20, 30, 80, 90, 100]
end

# @testset "categorical element decoder, classes, int " begin

    # @test_throws DomainError int("g")

    # N = 10
    # mix = shuffle(0:N - 1)
    #
    # Xraw = broadcast(x->mod(x,N), rand(Int, 2N, 3N))
    # Yraw = string.(Xraw)
    #
    # # to turn a categ matrix into a ordinary array with categorical
    # # elements. Need because broacasting the identity gives a
    # # categorical array in CategoricalArrays >0.5.2
    # function matrix_(X)
    #     ret = Array{Any}(undef, size(X))
    #     for i in eachindex(X)
    #         ret[i] = X[i]
    #     end
    #     return ret
    # end
    #
    # X = categorical(Xraw)
    # x = X[1]
    # Y = categorical(Yraw)
    # y = Y[1]
    # V = matrix_(X)
    # W = matrix_(Y)
    # Xo = levels!(deepcopy(X), mix)
    # xo = Xo[1]
    # Yo = levels!(deepcopy(Y), string.(mix))
    # yo = Yo[1]
    # Vo = matrix_(Xo)
    # Wo = matrix_(Yo)
    #
    # raw(x::CategoricalElement) = x.pool.index[x.level]
    # @test raw.(classes(xo)) == xo.pool.levels
    # @test raw.(classes(yo)) == yo.pool.levels

    # # getting all possible elements from one:
    # @test raw.(X) == Xraw
    # @test raw.(Y) == Yraw
    # @test raw.(classes(xo)) == levels(Xo)
    # @test raw.(classes(yo)) == levels(Yo)

    # # broadcasted encoding:
    # @test int(X) == int(V)
    # @test int(Y) == int(W)

    # @test int(X, type=Int8) isa AbstractArray{Int8}

    # # encoding is right-inverse to decoding:
    # d = decoder(xo)
    # @test d(int(Vo)) == Vo # ie have the same elements
    # e = decoder(yo)
    # @test e(int(Wo)) == Wo

    # # classes return value is in correct order:
    # int(classes(xo)) == 1:length(classes(xo))

#    levels!(Yo, reverse(levels(Yo)))
#    e = decoder(yo)
#    @test e(int(Wo)) == Wo

# XXX removed

    # # int is based on ordering not index
    # v = categorical(['a', 'b', 'c'], ordered=true)
    # @test int(v) == 1:3
    # levels!(v, ['c', 'a', 'b'])
    # @test int(v) == [2, 3, 1]
    #
    # # special private int(pool, level) method:
    # @test broadcast(int, [d.pool], levels(Xo)) == int.(classes(xo))
    # levels!(Xo, reverse(levels(Xo)))
    # @test broadcast(int, [d.pool], levels(Xo)) == int.(classes(xo))

# end

# @testset "table to matrix to table" begin
#
#     B = rand(UInt8, (4, 5))
#     @test matrix(DataFrame(B)) == B
#     @test matrix(table(B)) == B
#     @test matrix(table(B), transpose=true) == B'
#
#     X  = (x1=rand(5), x2=rand(5))
#
#     @test table(X, prototype=DataFrame()) == DataFrame(X)
#     T = table((x1=(1,2,3), x2=(:x, :y, :z)))
#     selectcols(T, :x1) == [1, 2, 3]
#
#     v = categorical(11:20)
#     A = hcat(v, v)
#     tab = table(A)
#     selectcols(tab, 1) == v
#
#     @test matrix(B) == B
#     @test matrix(B, transpose=true) == permutedims(B)
#
# end

## TABLE INDEXING

# A = broadcast(x->Char(65+mod(x,5)), rand(Int, 10, 5))
# X = CategoricalArrays.categorical(A)
#
# df = DataFrame(A)

# uncomment 4 lines to restore JuliaDB testing:
# db = JuliaDB.table(tt)
# nd = ndsparse((document=[6, 1, 1, 2, 3, 4],
#                word=[:house, :house, :sofa, :sofa, :chair, :house]), (values=["big", "small", 17, 34, 4, "small"],))

# df.z  = 1:10
# tt = TypedTables.Table(df)
# rt = Tables.rowtable(tt)
# ct = Tables.columntable(tt)
# uncomment 1 line to restore JuliaDB testing:
# db = JuliaDB.table(tt)

# @test selectcols(nothing, 4:6) == nothing
# @test selectcols(df, 4:6) == df[:,4:6]
# @test selectcols(df, [:x1, :z]) == df[:,[:x1, :z]]
# @test selectcols(df, :x2) == df.x2
# @test selectcols(nothing, 4:6) == nothing
# @test selectcols(df, 2) == df.x2
# @test selectrows(df, 4:6) == selectrows(df[4:6, :], :)
# @test selectrows(df, 1) == selectrows(df[1:1, :], :)
# @test selectrows(nothing, 4:6) == nothing
# @test select(df, 2, :x2) == df[2,:x2]
# @test select(nothing, 2, :x) == nothing
# s = schema(df)
# @test nrows(df) == size(df, 1)

# @test selectcols(tt, 4:6) == selectcols(TypedTables.Table(x4=tt.x4, x5=tt.x5, z=tt.z), :)
# @test selectcols(tt, [:x1, :z]) == selectcols(TypedTables.Table(x1=tt.x1, z=tt.z), :)
# @test selectcols(tt, :x2) == tt.x2
# @test selectcols(tt, 2) == tt.x2
# @test selectrows(tt, 4:6) == selectrows(tt[4:6], :)
# @test nrows(tt) == length(tt.x1)
# @test select(tt, 2, :x2) == tt.x2[2]
#
# @test selectrows(rt, 4:6) == rt[4:6]
# @test selectrows(rt, :) == rt
# @test selectrows(rt, 5) == view(rt, 5)
#
# @test Tables.rowtable(selectrows(ct, 4:6)) == rt[4:6]
# @test selectrows(ct, :) == ct
# @test Tables.rowtable(selectrows(ct, 5))[1] == view(rt, 5)[1]


# @testset "vector accessors" begin
#     v = rand(Int, 4)
#     @test selectrows(v, 2:3) == v[2:3]
#     @test selectrows(v, 2) == [v[2]]
#     @test nrows(v) == 4
#
#     v = categorical(collect("asdfasdf"))
#     @test selectrows(v, 2:3) == v[2:3]
#     @test selectrows(v, 2) == [v[2]]
#     @test nrows(v) == 8
# end

# @testset "matrix accessors" begin
#     A = rand(5, 10)
#     @test selectrows(A, 2:4) == A[2:4,:]
#     @test selectrows(A, 2:4) == A[2:4,:]
#     @test selectrows(A, 2) == A[2:2,:]
#
#     A = rand(5, 10) |> categorical
#     @test selectrows(A, 2:4) == A[2:4,:]
#     @test selectrows(A, 2:4) == A[2:4,:]
#     @test selectrows(A, 2) == A[2:2,:]
#
#     @test nrows(A) == 5
# end

# v = categorical(collect("asdfasdf"))
# df = DataFrame(v=v, w=v)
# @test selectcols(df, :w) == v
# tt = TypedTables.Table(df)
# # uncomment 1 line to restore JuliaDB testing:
# # db = JuliaDB.table(tt)
# @test selectcols(tt, :w) == v
# uncomment 1 line to restore JuliaDB testing:
# @test selectcols(db, :w) == v

# uncomment 9 lines to restore JuliaDB testing:
# @test select(nd, 2, :house) isa Missing
# @test select(nd, 1, :house) == "small"
# @test all(select(nd, :, :house) .=== ["small", missing, missing, "small", missing, "big"])
# @test all(select(nd, [2,4], :house) .=== [missing, "small"])
# @test all(selectcols(nd, :house) .=== select(nd, :, :house))
# @test nrows(nd) == 6
# s = schema(nd)
# @test s.names == (:chair, :house, :sofa)
# @test s.types == (Union{Missing,Int64}, Union{Missing,String}, Union{Missing,Int64})






# uncomment 3 lines to restore JuliaDB testing:
# sparsearray = sparse([6, 1, 1, 2, 3, 4], [2, 2, 3, 3, 1, 2],
#                      ["big", "small", 17, 34, 4, "small"])
# @test matrix(nd) == sparsearray

@testset "coverage" begin
    @test_throws DomainError partition(1:10, 1.5)

    @test_throws ArgumentError selectrows(Val(:other), (1,), (1,))
    @test_throws ArgumentError selectcols(Val(:other), (1,), (1,))
    @test_throws ArgumentError select(Val(:other), (1,), (1,), (1,))
    @test_throws ArgumentError nrows(Val(:other), (1,))

    nt = (a=5, b=7)
    @test MLJBase.project(nt, :) == (a=5, b=7)
    @test MLJBase.project(nt, :a) == (a=5, )
    @test MLJBase.project(nt, 1) == (a=5, )

    X = MLJBase.table((x=[1,2,3], y=[4,5,6]))
    @test select(Val(:table), X, 1, :y) == 4
end

end # module

true
